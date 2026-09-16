# The nixie.* option tree as data for the installer: path, type, default,
# description and the wizard metadata. The wizard renders descriptions
# verbatim, which is why they are written for people.
{ lib }:
options:
let
  typeName = t: t.description or t.name;
  wizard = import ./wizard.nix;
  enumValues = t: if t.name == "enum" then t.functor.payload.values or [ ] else [ ];
  walk =
    o:
    if lib.isOption o then
      [
        {
          path = lib.showOption o.loc;
          type = typeName o.type;
          # A free-form option can still offer the wizard a list.
          values = o.nixieUi.values or (enumValues o.type);
          default = if o ? defaultText then toString o.defaultText else o.default or null;
          required = !(o ? default);
          description = o.description or "";
          section = o.nixieUi.section or null;
          label = wizard.${lib.showOption o.loc}.label or null;
          advanced = wizard.${lib.showOption o.loc}.advanced or false;
          picker = wizard.${lib.showOption o.loc}.picker or null;
          order = o.nixieUi.order or 0;
          secret = o.nixieUi.secret or null;
          readOnly = o.readOnly or false;
        }
      ]
    else if lib.isAttrs o then
      lib.concatMap walk (lib.attrValues (lib.filterAttrs (n: _: n != "_module") o))
    else
      [ ];
  serialisable =
    v:
    if builtins.isFunction v || lib.isDerivation v then
      null
    else if lib.isAttrs v then
      lib.mapAttrs (_: serialisable) v
    else if lib.isList v then
      map serialisable v
    else
      v;
in
builtins.toJSON (
  map (o: o // { default = serialisable o.default; }) (
    lib.filter (o: !o.readOnly) (walk options.nixie)
  )
)
