using Godot;
using Glyphwake.Glyphs;

namespace Glyphwake.Player;

/// The player's resource pools: what a glyph's cost is paid out of. Until this existed,
/// <see cref="GlyphCost"/> described spends nothing could check or pay. Health and stamina
/// have no spender yet -- the pools are built together so a cost entry's resource is enough
/// to reach one when their glyphs arrive.
///
/// Recovery is the slow passive regeneration at all times (GlyphDecisions.md, "Recovery of
/// Resources"): safe zones, resting and regen passives boost it later, so the rates are the
/// floor everything else adds to. They are exports rather than StatKey reads because a
/// passive that modifies them is the resolver layer, which does not exist yet.
public partial class PlayerResources : Node
{
    [Export] public float MaxMana = 100f;
    [Export] public float ManaRecovery = 5f;

    [Export] public float MaxHealth = 100f;
    [Export] public float HealthRecovery = 1f;

    [Export] public float MaxStamina = 100f;
    [Export] public float StaminaRecovery = 10f;

    private float _mana;
    private float _health;
    private float _stamina;

    public float Mana => _mana;
    public float Health => _health;
    public float Stamina => _stamina;

    public override void _Ready()
    {
        _mana = MaxMana;
        _health = MaxHealth;
        _stamina = MaxStamina;
    }

    public override void _PhysicsProcess(double delta)
    {
        // Min against the max rather than only clamping the gain: a max retuned at runtime
        // -- which the tests do -- takes the current value down with it on the next tick.
        float dt = (float)delta;
        _mana = Mathf.Min(MaxMana, _mana + ManaRecovery * dt);
        _health = Mathf.Min(MaxHealth, _health + HealthRecovery * dt);
        _stamina = Mathf.Min(MaxStamina, _stamina + StaminaRecovery * dt);
    }

    public bool CanSpend(CostResource resource, float amount) =>
        Current(resource) >= amount;

    /// Pays a spend out of one pool. Refuses a negative amount, so a caller cannot turn a
    /// cost into a refund by accident; refunds are a deliberate call when one exists.
    public bool TrySpend(CostResource resource, float amount)
    {
        float current = Current(resource);
        if (amount < 0f || current < amount)
            return false;

        Set(resource, current - amount);
        return true;
    }

    public float Current(CostResource resource) => resource switch
    {
        CostResource.Mana => _mana,
        CostResource.Health => _health,
        CostResource.Stamina => _stamina,
        _ => 0f
    };

    private void Set(CostResource resource, float value)
    {
        switch (resource)
        {
            case CostResource.Mana:
                _mana = value;
                break;
            case CostResource.Health:
                _health = value;
                break;
            case CostResource.Stamina:
                _stamina = value;
                break;
        }
    }
}
