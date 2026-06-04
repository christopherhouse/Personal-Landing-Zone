# Cross-entity invariants and derived names.
#
# All assertions live here (not in variables.tf validation {} blocks) because
# they reason about multiple variables at once — e.g., "does every spoke's
# subscription_slot exist in subscription_slots", or "are all spoke address
# spaces disjoint from each other and from the hub".
#
# Failures surface as preconditions on terraform_data resources at the bottom
# of this file, which halt `tofu plan` with the conflicting pair / object
# named, per data-model.md "Cross-entity invariants".

locals {
  # ------------------------------------------------------------------
  # (a) address_blocks — full list for operator visibility.
  # ------------------------------------------------------------------
  # Includes hub address space, VPN client pool, every spoke address space,
  # and every workload subnet prefix. The overlap check (below) operates on
  # the "primary allocations" subset (hub + VPN + spoke address_space values)
  # because workload subnets are by design strict subsets of their parent
  # spoke's address_space — see data-model.md "Cross-entity invariants" 2 & 3.
  primary_allocations = concat(
    [{
      label = "hub_address_space"
      cidr  = var.platform.hub_address_space
    }],
    [{
      label = "vpn_client_address_pool"
      cidr  = var.platform.vpn_client_address_pool
    }],
    [for k, s in var.spokes : {
      label = "spoke:${k}:address_space"
      cidr  = s.address_space
    }],
  )

  workload_subnets = [for k, s in var.spokes : {
    label  = "spoke:${k}:workload_subnet"
    cidr   = s.workload_subnet_prefix
    parent = s.address_space
    spoke  = k
  }]

  # ------------------------------------------------------------------
  # CIDR → (start, end) numeric ranges for overlap math.
  # ------------------------------------------------------------------
  # Avoids depending on OpenTofu user-defined functions; works with stock
  # built-in functions only.
  primary_allocations_numeric = [
    for block in local.primary_allocations : merge(block, {
      start = sum([
        for i, octet in split(".", split("/", block.cidr)[0]) :
        tonumber(octet) * pow(256, 3 - i)
      ])
      end = sum([
        for i, octet in split(".", split("/", block.cidr)[0]) :
        tonumber(octet) * pow(256, 3 - i)
      ]) + pow(2, 32 - tonumber(split("/", block.cidr)[1])) - 1
    })
  ]

  # ------------------------------------------------------------------
  # (b) Pairwise non-overlap of primary allocations.
  # ------------------------------------------------------------------
  overlapping_pairs = [
    for pair in setproduct(local.primary_allocations_numeric, local.primary_allocations_numeric) :
    {
      a      = pair[0].label
      a_cidr = pair[0].cidr
      b      = pair[1].label
      b_cidr = pair[1].cidr
    }
    # Dedupe (A,B)/(B,A) and skip (A,A) via lexicographic compare. HCL's `<`
    # is numeric-only; use strcontains/regex-free compare via index lookup.
    if index(
      [for b in local.primary_allocations_numeric : b.label],
      pair[0].label,
      ) < index(
      [for b in local.primary_allocations_numeric : b.label],
      pair[1].label,
    ) &&
    pair[0].start <= pair[1].end &&
    pair[1].start <= pair[0].end
  ]

  # ------------------------------------------------------------------
  # Subnet containment — workload_subnet_prefix must be inside its
  # spoke's address_space.
  # ------------------------------------------------------------------
  workload_subnets_numeric = [
    for s in local.workload_subnets : merge(s, {
      child_start = sum([
        for i, octet in split(".", split("/", s.cidr)[0]) :
        tonumber(octet) * pow(256, 3 - i)
      ])
      child_end = sum([
        for i, octet in split(".", split("/", s.cidr)[0]) :
        tonumber(octet) * pow(256, 3 - i)
      ]) + pow(2, 32 - tonumber(split("/", s.cidr)[1])) - 1
      parent_start = sum([
        for i, octet in split(".", split("/", s.parent)[0]) :
        tonumber(octet) * pow(256, 3 - i)
      ])
      parent_end = sum([
        for i, octet in split(".", split("/", s.parent)[0]) :
        tonumber(octet) * pow(256, 3 - i)
      ]) + pow(2, 32 - tonumber(split("/", s.parent)[1])) - 1
    })
  ]

  uncontained_subnets = [
    for s in local.workload_subnets_numeric : {
      spoke           = s.spoke
      workload_subnet = s.cidr
      address_space   = s.parent
    }
    if s.child_start < s.parent_start || s.child_end > s.parent_end
  ]

  # ------------------------------------------------------------------
  # (c) Every distinct subscription_slot referenced by a spoke must
  #     exist as a key in subscription_slots.
  # ------------------------------------------------------------------
  unknown_slot_refs = [
    for k, s in var.spokes : {
      spoke = k
      slot  = s.subscription_slot
    }
    if !contains(keys(var.subscription_slots), s.subscription_slot)
  ]

  # The hub slot's subscription_id must equal platform.hub_subscription_id.
  hub_slot_mismatch = (
    contains(keys(var.subscription_slots), "hub") &&
    var.subscription_slots["hub"].subscription_id != var.platform.hub_subscription_id
  )

  # ------------------------------------------------------------------
  # (d) Spoke names (map keys) are inherently unique in HCL; spoke
  #     resource_group_name values must also be unique across the inventory.
  # ------------------------------------------------------------------
  rg_name_counts = {
    for k, s in var.spokes :
    s.resource_group_name => k...
  }
  duplicate_rg_names = {
    for rg, spokes in local.rg_name_counts :
    rg => spokes if length(spokes) > 1
  }

  # ------------------------------------------------------------------
  # (e) At most one spoke may set include_validation_workload = true.
  # ------------------------------------------------------------------
  validation_workload_spokes = [
    for k, s in var.spokes : k
    if try(s.include_validation_workload, false)
  ]

  # Derived naming locals previously declared here are dead — each module
  # (hub, spoke, validation) builds its own resource names internally from
  # the naming_prefix it is passed. Adding any global cross-module naming
  # convention later would re-introduce them here.
}

# --------------------------------------------------------------------
# Assertion resources. These are terraform_data resources whose only
# purpose is to surface invariant failures as `tofu plan` errors, with a
# clear message naming the conflicting objects. They do nothing at apply
# time beyond existing.
# --------------------------------------------------------------------

resource "terraform_data" "assert_address_space_non_overlap" {
  input = local.overlapping_pairs
  lifecycle {
    precondition {
      condition     = length(local.overlapping_pairs) == 0
      error_message = format("Address-space overlap detected. Conflicting allocations: %s", jsonencode(local.overlapping_pairs))
    }
  }
}

resource "terraform_data" "assert_workload_subnets_contained" {
  input = local.uncontained_subnets
  lifecycle {
    precondition {
      condition     = length(local.uncontained_subnets) == 0
      error_message = format("Workload subnet(s) not contained within their spoke address_space: %s", jsonencode(local.uncontained_subnets))
    }
  }
}

resource "terraform_data" "assert_known_subscription_slots" {
  input = local.unknown_slot_refs
  lifecycle {
    precondition {
      condition     = length(local.unknown_slot_refs) == 0
      error_message = format("Spoke(s) reference unknown subscription slot(s). Add a provider alias to infra/providers.tf and a subscription_slots entry first. Unknown references: %s", jsonencode(local.unknown_slot_refs))
    }
  }
}

resource "terraform_data" "assert_hub_slot_matches_platform" {
  input = local.hub_slot_mismatch
  lifecycle {
    precondition {
      condition     = !local.hub_slot_mismatch
      error_message = "subscription_slots[\"hub\"].subscription_id must equal platform.hub_subscription_id."
    }
  }
}

resource "terraform_data" "assert_unique_spoke_rg_names" {
  input = local.duplicate_rg_names
  lifecycle {
    precondition {
      condition     = length(local.duplicate_rg_names) == 0
      error_message = format("Duplicate spoke.resource_group_name values detected (each must be unique across the inventory): %s", jsonencode(local.duplicate_rg_names))
    }
  }
}

resource "terraform_data" "assert_at_most_one_validation_workload" {
  input = local.validation_workload_spokes
  lifecycle {
    precondition {
      condition     = length(local.validation_workload_spokes) <= 1
      error_message = format("At most one spoke may set include_validation_workload = true. Currently set on: %s", jsonencode(local.validation_workload_spokes))
    }
  }
}
