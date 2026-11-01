{
    inputs = {
        nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
        nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs-unstable";
        };
        # Fast nix-eval
        determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
        # Niri
        # niri = {
        #     url = "github:sodiboo/niri-flake";
        #     inputs.nixpkgs.follows = "nixpkgs-unstable";
        # };
        # Libs
        nix-index-database = { # Needs for nix-index and comma fast search/index
            url = "github:nix-community/nix-index-database";
            inputs.nixpkgs.follows = "nixpkgs-unstable";
        };
        # All my common modules
        common.url = "git+file:///etc/nixos/common";
    };
    outputs = inputs@{ self, nixpkgs-stable, nixpkgs-unstable, home-manager, common, ... }:
        let
            vars = import ./vars.nix;
            # my lib functions and packages (common/lib, common/pkgs, ./lib, ./pkgs; see common/handmade.nix)
            handmade = import (common.path + /handmade.nix) {
                inherit (nixpkgs-unstable) lib;
                inherit vars;
                com = common.path;
                cur = ./.;
            };
            mkLib = nixpkgs: (nixpkgs.lib
                .extend (final: prev: handmade.myLibs (common.path + /lib) final prev))
                .extend (final: prev: handmade.myLibs ./lib final prev); # a host function replaces a common one, a host group extends it

            pkgsConfig = {
                localSystem = vars.arch; # nixpkgs has no hostPlatform argument; without localSystem it asks builtins.currentSystem (impure only)
                config = {
                    allowUnfree = true;
                };
            };
            # every overlay lives here, so pkgs.stable gets them too (lazy: unused packages cost nothing)
            mkPkgsOverlays = nixpkgs:
                (import nixpkgs pkgsConfig).appendOverlays [
                    (final: prev: { lib = mkLib nixpkgs; }) # Normal lib everywhere
                    (handmade.myPkgs (common.path + /pkgs))
                    (handmade.myPkgs ./pkgs) # a host package replaces a common one, a host group extends it
                    (final: prev: {
                        # the same nix the determinate module installs; otherwise comma warns about eval-cores/lazy-trees
                        comma = prev.comma.override { nix = inputs.determinate.inputs.nix.packages.${vars.arch}.default; };
                    })
                ];
            pkgs = (mkPkgsOverlays nixpkgs-unstable).appendOverlays [
                (final: prev: { stable = mkPkgsOverlays nixpkgs-stable; })
            ];

            # HM builds its modules' lib from pkgs.lib itself, so they see my functions without specialArgs
            mkHome = vars: home-manager.lib.homeManagerConfiguration {
                inherit pkgs;
                extraSpecialArgs = {
                    inherit vars;
                    com = common.path; # path to the common flake
                    cur = ./.;         # path to this flake
                };
                modules = [
                    # inputs.niri.homeModules.niri
                    ./hm/${vars.user}/_home.nix # _ hides it from get
                ];
            };
        in {
            nixosConfigurations.${vars.host} = pkgs.lib.nixosSystem {
                inherit pkgs;
                inherit (pkgs) lib;
                specialArgs = {
                    inherit vars;
                    com = common.path; # path to the common flake
                    cur = ./.;         # path to this flake
                };
                modules = [
                    inputs.determinate.nixosModules.default
                    inputs.nix-index-database.nixosModules.nix-index
                    ./sys/_config.nix         # _ hides it from get
                ];
            };
            homeConfigurations = pkgs.lib.mergeAttrsList (builtins.map (user: {
                "${user}@${vars.host}" = mkHome (vars // { inherit user; });
            }) ([ "root" ] ++ vars.users));
        };
}
