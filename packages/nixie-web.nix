# The control panel and the installer wizard: one npm workspace, one
# vendored lockfile, no network at runtime. Fonts are copied in at build
# time from a pinned OFL source and nixpkgs.
{ pkgs }:
let
  archivo = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/google/fonts/8e44913e4ff26fc997e6856c1ec40ff4791c98c5/ofl/archivo/Archivo%5Bwdth%2Cwght%5D.ttf";
    hash = "sha256-DglKfTx8TCXPExDEswAU8drpMyIgscLIj0+plvCwUFM=";
    name = "Archivo.ttf";
  };
  web = pkgs.buildNpmPackage {
    pname = "nixie-web";
    version = "0.1.0";
    src = pkgs.lib.cleanSourceWith {
      src = ../ui;
      filter = p: _: !(pkgs.lib.hasInfix "node_modules" p || pkgs.lib.hasInfix "/dist" p);
    };
    npmDepsHash = "sha256-43RzHJMN71ObbZeJr2epDCry8jUJhzeN3mInQVgxT2w=";
    # The dashboards JSON is imported from the repo root.
    postPatch = ''
      mkdir -p ../dashboards
      cp ${../dashboards}/*.json ../dashboards/
    '';
    installPhase = ''
      mkdir -p $out
      cp -r dist/. $out/
      mkdir -p $out/fonts $out/setup/fonts
      cp ${archivo} $out/fonts/Archivo.ttf
      cp ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf $out/fonts/
      cp ${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Medium.ttf $out/fonts/
      cp $out/fonts/* $out/setup/fonts/
    '';
  };
in
{
  inherit web archivo;
  nixie-ui = pkgs.runCommand "nixie-ui" { } ''
    mkdir -p $out
    cp -r ${web}/assets ${web}/fonts ${web}/index.html $out/
  '';
  nixie-setup-web = pkgs.runCommand "nixie-setup-web" { } ''
    mkdir -p $out
    cp -r ${web}/setup/. $out/
    cp -r ${web}/assets $out/assets
  '';
}
