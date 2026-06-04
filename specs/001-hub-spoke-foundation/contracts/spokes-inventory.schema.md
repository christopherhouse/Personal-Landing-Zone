# Contract: `config/spokes.auto.tfvars`

**Owner**: operator | **Consumer**: `infra/` OpenTofu root | **Reload**: per `tofu plan`

The spokes inventory is the operator's primary day-2 interface. Editing this file (and only this file) is the supported way to add, modify, or remove a spoke when the target subscription already has a slot declared.

## HCL shape

```hcl
spokes = {
  "<logical_name>" = {
    subscription_slot           = "<slot_name>"
    resource_group_name         = "<rg_name>"
    address_space               = "<cidr>"
    workload_subnet_prefix      = "<cidr>"
    include_validation_workload = <bool>   # optional, default false
    dns_zone_links              = [        # optional, defaults to all hub zones
      "<zone_fqdn>", ...
    ]
    tags                        = {        # optional
      "<key>" = "<value>"
    }
  }
}
```

## Field-by-field contract

### `<logical_name>` (map key)

- **Type**: string
- **Required**: yes
- **Pattern**: `^[a-z][a-z0-9-]{1,38}[a-z0-9]$` — lowercase, hyphens allowed, must start with a letter and end with a letter or digit, total length 3–40.
- **Uniqueness**: unique across the inventory.
- **Used in**: every spoke resource name (e.g., `vnet-plz-spoke-<name>`).
- **Mutation**: renaming is a destroy+create of the entire spoke. To rename safely, do it in two PRs: PR1 adds the new name with the same address space (will fail validation due to overlap, so this is effectively forbidden) → in practice, never rename. Pick the name carefully on first add.

### `subscription_slot`

- **Type**: string
- **Required**: yes
- **Allowed values**: any key in `subscription_slots` declared in `config/subscriptions.auto.tfvars`.
- **Failure**: if the named slot doesn't exist, `tofu plan` halts with `"Spoke '<name>' references unknown subscription slot '<slot>'. Add a provider alias and a subscription_slots entry first."`
- **Mutation**: changing the slot moves the spoke to a different subscription, which is a destroy+create. Don't.

### `resource_group_name`

- **Type**: string
- **Required**: yes
- **Pattern**: `^rg-[a-z0-9-]+$`
- **Uniqueness**: unique across the inventory.
- **Created by**: the platform (must NOT pre-exist in the target subscription).
- **Mutation**: changing this is a destroy+create. Don't.

### `address_space`

- **Type**: CIDR string
- **Required**: yes
- **Recommended size**: `/22` (matches the default allocation scheme).
- **Constraints**:
  - Must NOT overlap with `platform.hub_address_space`.
  - Must NOT overlap with `platform.vpn_client_address_pool`.
  - Must NOT overlap with any other spoke's `address_space`.
- **Validation**: enforced in `infra/locals.tf`; failure halts plan with the conflicting pair named.

### `workload_subnet_prefix`

- **Type**: CIDR string
- **Required**: yes
- **Constraint**: must be a strict subset of `address_space`.
- **Recommended size**: `/24` (matches the default allocation scheme — `address_space` `10.<x>.0.0/22`, workload subnet `10.<x>.0.0/24`).

### `include_validation_workload`

- **Type**: bool
- **Required**: no
- **Default**: `false`
- **Semantics**: when `true`, the platform deploys the validation workload (B1s VM + storage PE) into this spoke. At most one spoke may set this `true`; multiple instances are rejected at plan time.
- **Typical use**: set `true` on the `validation` spoke only.

### `dns_zone_links`

- **Type**: `list(string)` of fully-qualified zone names
- **Required**: no
- **Default**: all zones in `platform.dns_zones` (every spoke is linked to every hub zone).
- **Semantics**: explicit opt-out from selected zones. Each listed value must appear in `platform.dns_zones` — unknown zones halt plan.
- **Typical use**: leave unset.

### `tags`

- **Type**: `map(string)`
- **Required**: no
- **Default**: `{}`
- **Semantics**: merged with the inherited platform-level tags. Spoke-level tags win on key collision.

## Worked examples

### Initial inventory (post-bootstrap)

```hcl
spokes = {
  validation = {
    subscription_slot           = "hub"
    resource_group_name         = "rg-plz-spoke-validation-eastus2"
    address_space               = "10.1.0.0/22"
    workload_subnet_prefix      = "10.1.0.0/24"
    include_validation_workload = true
  }
}
```

### Adding a second spoke in the same subscription

```hcl
spokes = {
  validation = { ... }              # unchanged
  acme-demo = {
    subscription_slot     = "hub"
    resource_group_name   = "rg-acme-demo-eastus2"
    address_space         = "10.2.0.0/22"
    workload_subnet_prefix = "10.2.0.0/24"
  }
}
```

### Adding a spoke in a *different* subscription

Requires two files to change (still configuration-only):

```hcl
# config/subscriptions.auto.tfvars
subscription_slots = {
  hub    = { subscription_id = "..." }
  demo_a = { subscription_id = "..." }   # ← new
}
```

```hcl
# config/spokes.auto.tfvars
spokes = {
  validation = { ... }
  acme-demo  = {
    subscription_slot     = "demo_a"     # ← references new slot
    resource_group_name   = "rg-acme-demo-eastus2"
    address_space         = "10.2.0.0/22"
    workload_subnet_prefix = "10.2.0.0/24"
  }
}
```

If `demo_a` did not already have a corresponding `provider "azurerm" { alias = "sub_demo_a" ... }` block in `infra/providers.tf`, the plan will fail at validation. Adding the provider alias is the one-time HCL edit when introducing a new subscription (see `bootstrap-inputs.md`).

## Acceptance scenarios this contract supports

- **AS-2.1** (FR-008, FR-009): operator edits this file, opens PR, merges → new spoke deployed.
- **AS-2.3** (FR-011, FR-012): operator submits overlapping CIDR or duplicate RG name → plan rejects with named conflict.
- **AS-3.1** (FR-010): operator removes a spoke entry → destroy plan removes RG and all its resources.
