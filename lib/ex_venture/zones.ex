defmodule ExVenture.Zones.Zone do
  @moduledoc """
  Schema for Zones
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias ExVenture.Rooms.Room
  alias ExVenture.StagedChanges.StagedChange

  schema "zones" do
    field(:name, :string)
    field(:description, :string)

    belongs_to(:graveyard, Room)
    has_many(:rooms, Room)

    has_many(:staged_changes, {"zone_staged_changes", StagedChange}, foreign_key: :record_id)

    timestamps()
  end

  def create_changeset(struct, params) do
    struct
    |> cast(params, [:name, :description, :graveyard_id])
    |> validate_required([:name, :description])
    |> foreign_key_constraint(:graveyard_id)
  end

  def update_changeset(struct, params) do
    struct
    |> cast(params, [:name, :description, :graveyard_id])
    |> validate_required([:name, :description])
    |> foreign_key_constraint(:graveyard_id)
  end
end

defmodule ExVenture.Zones do
  @moduledoc """
  CRUD Zones
  """

  import Ecto.Query

  alias ExVenture.Repo
  alias ExVenture.StagedChanges
  alias ExVenture.StagedChanges.StagedChange
  alias ExVenture.Zones.Zone

  def new(), do: Ecto.Changeset.change(%Zone{}, %{})

  def edit(zone), do: Ecto.Changeset.change(zone, %{})

  @doc """
  Get all zones, paginated
  """
  def all(opts \\ []) do
    opts = Enum.into(opts, %{})

    Zone
    |> preload(:staged_changes)
    |> Repo.paginate(opts[:page], opts[:per])
    |> staged_changes()
  end

  def staged_changes(%{page: zones, pagination: pagination}) do
    zones = Enum.map(zones, &StagedChanges.apply/1)
    %{page: zones, pagination: pagination}
  end

  def staged_changes(zones) do
    Enum.map(zones, &StagedChanges.apply/1)
  end

  @doc """
  Get a zone
  """
  def get(id) do
    case Repo.get(Zone, id) do
      nil ->
        {:error, :not_found}

      zone ->
        zone =
          zone
          |> Repo.preload(:staged_changes)
          |> StagedChanges.apply()

        {:ok, zone}
    end
  end

  @doc """
  Create a new zone
  """
  def create(params) do
    %Zone{}
    |> Zone.create_changeset(params)
    |> Repo.insert()
  end

  @doc """
  Update a zone
  """
  def update(zone, params) do
    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:changeset, fn _repo, _changes ->
        zone
        |> Zone.update_changeset(params)
        |> StagedChanges.apply_action(:update)
      end)
      |> Ecto.Multi.merge(fn %{changeset: changeset} ->
        Enum.reduce(changeset.changes, Ecto.Multi.new(), fn {attribute, value}, multi ->
          staged_change = Ecto.build_assoc(zone, :staged_changes)
          changeset = StagedChange.create_changeset(staged_change, zone.id, attribute, value)

          Ecto.Multi.insert(multi, {:staged_change, attribute}, changeset,
            on_conflict: {:replace, [:value]},
            conflict_target: [:record_id, :attribute]
          )
        end)
      end)
      |> Ecto.Multi.run(:zone, fn repo, %{changeset: changeset} ->
        zone = repo.preload(changeset.data, :staged_changes, force: true)
        zone = StagedChanges.apply(zone)
        {:ok, zone}
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{zone: zone}} ->
        {:ok, zone}

      {:error, :changeset, changeset, _changes} ->
        {:error, changeset}
    end
  end
end
