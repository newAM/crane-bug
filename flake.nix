{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rust-overlay.follows = "rust-overlay";
        flake-utils.follows = "flake-utils";
      };
    };
  };
  outputs = {self, nixpkgs, flake-utils, rust-overlay, crane}:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          system = "x86_64-linux";
          overlays = [(import rust-overlay)];
          pkgs = import nixpkgs {
            inherit system overlays;
          };
          inherit (pkgs) lib;
          rustToolchain = pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;
          src = lib.cleanSourceWith {
            src = ./.; # The original, unfiltered source
            filter = path: type:
              # Allow sql files for migrations
              (lib.hasSuffix "\.sql" path) ||
              # Default filter from crane (allow .rs files)
              (craneLib.filterCargoSources path type)
            ;
          };
          nativeBuildInputs = with pkgs; [rustToolchain pkg-config];
          buildInputs = with pkgs; [rustToolchain openssl postgresql_15.lib];
          developmentTools = with pkgs; [(diesel-cli.override {sqliteSupport = false; mysqlSupport = false;}) postgresql cargo];
          commonArgs = {
            inherit src buildInputs nativeBuildInputs;
          };
          cargoArtifacts = craneLib.buildDepsOnly(commonArgs // {
            cargoBuildCommand = "cargo build --locked --profile dev";
            cargoExtraArgs = "--bin crane-bug";
            doCheck = false;
            pname = "crane-bug";
          });
          binary = craneLib.buildPackage(commonArgs // {
            inherit cargoArtifacts;
            cargoBuildCommand = "cargo build --locked --profile dev";
            cargoExtraArgs = "--bin crane-bug";
            doCheck = false;
            pname = "crane-bug";
          });
        in
        with pkgs;
        {
          packages = {
            inherit binary;
            default = binary;
          };
          devShells.default = mkShell {
            inputsFrom = [binary];
            buildInputs = with pkgs; [dive wget];
            packages = developmentTools;
          };
        }

      );
}
