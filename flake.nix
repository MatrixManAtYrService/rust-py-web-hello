{
  description = "hello-web - Browser application using hello-wasm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Git input to hello-wasm local repository
    hello-wasm.url = "git+file:///Users/matt/src/hello-subflake/subflake-git/hello-wasm?ref=main";
  };

  outputs = { self, nixpkgs, flake-utils, hello-wasm }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Build the web application with transpiled WASM using buildNpmPackage
        # This installs jco as a project dependency (not packaging jco itself)
        helloWebApp = pkgs.buildNpmPackage {
          pname = "hello-web";
          version = "0.1.0";
          src = ./.;

          npmDepsHash = "sha256-D7T4+RCwyyXlvxBOfCkbCIu90IwYQbBCSRUi8VeI8cY=";

          # Copy WASM file before building
          preBuild = ''
            cp ${hello-wasm.packages.${system}.default}/lib/hello_wasm.wasm ./
          '';

          buildPhase = ''
            runHook preBuild

            # Transpile WASM to JS using jco (installed via npm)
            # --no-nodejs-compat: removes Node.js specific code
            # --tla-compat: avoids top-level await issues with some bundlers
            # --base64-cutoff=0: inline all WASM as base64 for browser compatibility
            # --valid-lifting-optimization: optimize string lifting
            npx jco transpile hello_wasm.wasm \
              -o dist/bindings \
              --tla-compat \
              --no-nodejs-compat \
              --base64-cutoff=0 \
              --valid-lifting-optimization

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out

            # Copy the HTML file
            cp src/index.html $out/index.html

            # Copy the transpiled bindings
            cp -r dist $out/

            # Copy preview2-shim from node_modules for browser imports
            mkdir -p $out/node_modules/@bytecodealliance
            cp -r node_modules/@bytecodealliance/preview2-shim $out/node_modules/@bytecodealliance/

            runHook postInstall
          '';
        };

      in
      {
        packages = {
          default = helloWebApp;
          hello-web = helloWebApp;
          # Re-export packages from subflakes
          hello-wasm = hello-wasm.packages.${system}.default;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            nodePackages.npm
            python3
          ];

          shellHook = ''
            echo "Hello Web Development Environment"
            echo ""
            echo "To develop:"
            echo "  1. Build WASM: cd ../hello-wasm && nix build"
            echo "  2. Copy WASM: cp ../hello-wasm/result/lib/hello_wasm.wasm ./"
            echo "  3. Transpile: npm install && npm run transpile"
            echo "  4. Serve: python -m http.server"
            echo ""
            echo "Or use: nix build .#hello-web"
          '';
        };
      });
}
