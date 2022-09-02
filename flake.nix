{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    tezos = {
      url = "github:marigold-dev/tezos-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, tezos, rust-overlay }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        rustOverlay = final: prev:
          let rustChannel = prev.rust-bin.nightly.latest;
          in {
            inherit rustChannel;
            rustc = rustChannel.minimal;
          };
      in rec {

        devShell = let
          rustDevOverlay = final: prev: {
            # rust-analyzer needs core source
            rustc-with-src =
              prev.rustc.override { extensions = [ "rust-src" ]; };
          };
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) rustOverlay rustDevOverlay ];
          };
        in pkgs.mkShell {
          name = "evtez-demo";
          buildInputs = with pkgs;
          with ocamlPackages; [
              glibc
              cmake
              ligo
              nixfmt
            ];
          shellHook = ''
            alias lcc="ligo compile contract"
            alias lce="ligo compile expression"
            alias lcp="ligo compile parameter"
            alias lcs="ligo compile storage"
            alias build="./do build contract"
            alias dryrun="./do dryrun contract"
            alias deploy="./do deploy contract"
          '';
        };

        packages = let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) rustOverlay ];
          };

          contract = pkgs.stdenv.mkDerivation {
            name = "liquid";
            src = ./.;

            buildInputs = with pkgs; [
              ligo
            ];


            installPhase = ''
                mkdir -p $out
                ligo compile contract $src/contract/src/liquid.mligo -e  liquid_main -s cameligo -o $out/liquid.tz
                INITSTORAGE=$(<$src/contract/src/storage/initial_storage.mligo)
                ligo compile storage $src/contract/src/liquid.mligo "$INITSTORAGE" -s cameligo  -e  liquid_main -o $out/liquid-storage.tz
              '';


          };

        in { inherit indexer visualizer contract; };

        defaultPackage = self.packages.${system}.indexer;
        apps = {
          indexer =
          flake-utils.lib.mkApp { drv = packages.${system}.indexer; };
          visualizer =
            flake-utils.lib.mkApp { drv = packages.${system}.visualizer; };
          };
      });
}
