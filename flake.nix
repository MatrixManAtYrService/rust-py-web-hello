{
  description = "hello-fancy - A fancy CLI app";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Git input to hello-py local repository
    hello-py.url = "git+file:///Users/matt/src/hello-subflakes/subflake-git/hello-py?ref=main";

    # Git input to hello-web local repository
    hello-web.url = "git+file:///Users/matt/src/hello-subflakes/subflake-git/hello-web?ref=main";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, uv2nix, pyproject-nix, pyproject-build-systems, hello-py, hello-web }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        python = pkgs.python312;

        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.;
        };

        pyprojectOverlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

        # Override to inject hello-py wheel from the subflake
        # This replaces the source that uv2nix resolved
        helloPyOverlay = final: prev: let
          # Extract the actual wheel file from the wheel package
          wheelPath = "${hello-py.packages.${system}.wheel}/hello_py-0.1.0-cp310-abi3-macosx_14_0_arm64.whl";
        in {
          hello-py = (prev.hello-py or (final.mkPythonEditablePackage { root = ./hello-py; })).overrideAttrs (old: {
            src = wheelPath;
            format = "wheel";
            dontUnpack = true;
            dontBuild = true;
            buildInputs = [];
            nativeBuildInputs = [ pkgs.unzip ];
            installPhase = ''
              mkdir -p $out/${python.sitePackages}
              ${pkgs.unzip}/bin/unzip -q ${wheelPath} -d $out/${python.sitePackages}
            '';
          });
        };

        pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope (
          nixpkgs.lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            pyprojectOverlay
            helloPyOverlay
          ]
        );

        editableOverlay = workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };

        editableHatchling = final: prev: {
          hello-fancy = prev.hello-fancy.overrideAttrs (old: {
            nativeBuildInputs =
              old.nativeBuildInputs
              ++ final.resolveBuildSystem {
                editables = [ ];
              };
          });
        };

        editablePythonSet = pythonSet.overrideScope (
          nixpkgs.lib.composeManyExtensions [
            editableOverlay
            editableHatchling
          ]
        );

        pythonEnv = pythonSet.mkVirtualEnv "hello-fancy" workspace.deps.default;

        # Access the derivation for the local project package
        helloFancyPackage = pythonSet.hello-fancy;
      in
      {
        packages = {
          default = pythonEnv;
          hello-fancy = helloFancyPackage;
          # Re-export packages from subflakes
          hello-py-wheel = hello-py.packages.${system}.wheel;
          hello-py-env = hello-py.packages.${system}.default;
          # WebAssembly packages
          hello-web = hello-web.packages.${system}.default;
          hello-wasm = hello-web.packages.${system}.hello-wasm;
        };

        apps = {
          default = {
            type = "app";
            program = "${pythonEnv}/bin/hello-fancy";
          };
          hello-fancy = {
            type = "app";
            program = "${pythonEnv}/bin/hello-fancy";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            (editablePythonSet.mkVirtualEnv "hello-fancy" workspace.deps.all)
            uv
            # Testing dependencies
            python312Packages.pytest
            python312Packages.selenium
            # Docker tools (client only, no daemon)
            docker-compose
            docker-client
          ];
          env = {
            UV_PYTHON = python.interpreter;
          };
          shellHook = ''
            export REPO_ROOT=$(pwd)

            # Auto-detect container runtime socket
            if [ -z "$DOCKER_HOST" ]; then
              for sock in \
                "$HOME/.colima/default/docker.sock" \
                "$HOME/.orbstack/run/docker.sock" \
                "$HOME/.docker/run/docker.sock" \
                "/var/run/docker.sock" \
                "$XDG_RUNTIME_DIR/podman/podman.sock"
              do
                if [ -S "$sock" ]; then
                  export DOCKER_HOST="unix://$sock"
                  echo "📦 Using container socket: $sock"
                  break
                fi
              done
            fi

            if [ -z "$DOCKER_HOST" ] && ! docker info >/dev/null 2>&1; then
              echo "⚠️  No container runtime found. Tests require Docker Desktop, colima, Podman, or OrbStack."
              echo "   Start your container runtime before running tests."
            fi

            echo ""
            echo "Development environment ready!"
            echo "hello-py is provided via Nix overlay from the subflake"
            echo ""
            echo "To run tests:"
            echo "  pytest tests/    # Requires container runtime (Docker/Podman/colima/OrbStack)"
            echo ""
            echo "To watch tests running:"
            echo "  Open http://localhost:7900 in browser (no password required)"
          '';
        };
      });
}
