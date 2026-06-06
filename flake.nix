{
  description = "cross-encoder/ms-marco-MiniLM-L6-v2 reranker model (HuggingFace), pinned by commit + per-file hash for offline loading (no egress).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pin = import ./pin.nix;
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;
        repo = "cross-encoder/ms-marco-MiniLM-L6-v2";

        # Assemble just the needed files into a plain directory CrossEncoder can load by path.
        model = pkgs.runCommand "ms-marco-MiniLM-L6-v2" { } (''
          mkdir -p "$out"
        '' + lib.concatStrings (lib.mapAttrsToList
          (file: hash: ''
            cp ${pkgs.fetchurl {
              url = "https://huggingface.co/${repo}/resolve/${pin.rev}/${file}";
              inherit hash;
            }} "$out/${file}"
          '')
          pin.hashes));

        # Bespoke (not flake-lib's mkUpdateVersion): the source is a HuggingFace model repo (commit + per-file hash table), which flake-lib has no strategy for.
        update-version = pkgs.writeShellApplication {
          name = "update-version";
          text = ''exec ${./update-version.sh} "$@"'';
        };
      in
      {
        packages = {
          inherit model update-version;
          default = model;
        };
      });
}
