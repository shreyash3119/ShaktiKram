-- Stage 3 / lightweight meal planning, nutrition targets and hydration (features 11 and 12).
-- Planning comes first: nothing here requires logging every food item.

create table meals (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  title text not null, category text not null, instructions text, image_ref text, notes text,
  calories_kcal numeric(7,1), protein_g numeric(7,1), carbs_g numeric(7,1), fat_g numeric(7,1), fibre_g numeric(7,1),
  nutrition_is_estimate boolean not null default false,
  constraint ck_meals_title_not_blank check (length(trim(title)) > 0),
  constraint ck_meals_nutrition_nonnegative check (coalesce(calories_kcal, 0) >= 0 and coalesce(protein_g, 0) >= 0 and coalesce(carbs_g, 0) >= 0
                                                    and coalesce(fat_g, 0) >= 0 and coalesce(fibre_g, 0) >= 0)
);
select pfs_attach('meals', 'editable');

create table meal_ingredients (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  meal_id uuid not null references meals (id),
  name text not null, quantity numeric(10,2), unit text, position integer not null default 1,
  calories_kcal numeric(7,1), protein_g numeric(7,1), carbs_g numeric(7,1), fat_g numeric(7,1), fibre_g numeric(7,1),
  constraint ck_meal_ingredients_name_not_blank check (length(trim(name)) > 0),
  constraint ck_meal_ingredients_quantity_nonnegative check (quantity is null or quantity >= 0)
);
create index idx_meal_ingredients_meal_id on meal_ingredients (meal_id);
select pfs_attach('meal_ingredients', 'editable');

-- A meal built from other saved meals (a reusable combination).
create table meal_components (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  meal_id uuid not null references meals (id),
  component_meal_id uuid not null references meals (id),
  servings numeric(6,2) not null default 1,
  constraint ck_meal_components_different check (meal_id <> component_meal_id),
  constraint ck_meal_components_servings_positive check (servings > 0)
);
create unique index uq_meal_components_alive on meal_components (meal_id, component_meal_id) where deleted_at is null;
select pfs_attach('meal_components', 'editable');

create table meal_plan_entries (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  local_date date not null, slot text not null, meal_id uuid not null references meals (id),
  servings numeric(6,2) not null default 1, status text not null default 'planned',
  replaced_by_meal_id uuid references meals (id), notes text,
  constraint ck_meal_plan_entries_servings_positive check (servings > 0),
  constraint ck_meal_plan_entries_replaced_has_meal check (status <> 'replaced' or replaced_by_meal_id is not null)
);
create index idx_meal_plan_entries_local_date on meal_plan_entries (local_date);
select pfs_attach('meal_plan_entries', 'editable');

-- Personal targets (versioned, one current set): protein, optional calories, hydration and steps.
create table personal_targets (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  entity_id uuid not null, version integer not null,
  effective_from timestamptz not null, effective_to timestamptz,
  previous_version_id uuid references personal_targets (id), change_reason text,
  protein_g numeric(6,1), calories_kcal numeric(7,1), water_ml integer, step_target integer,
  constraint ck_personal_targets_version_positive check (version >= 1),
  constraint ck_personal_targets_interval check (effective_to is null or effective_to >= effective_from),
  constraint ck_personal_targets_positive check (coalesce(protein_g, 1) > 0 and coalesce(calories_kcal, 1) > 0 and coalesce(water_ml, 1) > 0 and coalesce(step_target, 1) > 0),
  constraint uq_personal_targets_entity_id_version unique (entity_id, version),
  constraint ex_personal_targets_no_overlap exclude using gist (entity_id with =, tstzrange(effective_from, effective_to, '[)') with &&)
);
create unique index uq_personal_targets_one_current on personal_targets ((true)) where effective_to is null and deleted_at is null;
select pfs_attach('personal_targets', 'versioned', true);

create table water_logs (
  id uuid primary key default uuid_v7(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  deleted_at timestamptz, rev bigint not null default 0, device_id uuid,
  amount_ml integer not null,
  occurred_at timestamptz not null, local_date date not null, tz_offset_minutes smallint not null,
  constraint ck_water_logs_amount_positive check (amount_ml > 0)
);
create index idx_water_logs_local_date on water_logs (local_date);
select pfs_attach('water_logs', 'append_only', false, true);
