{
  description = "hello-wasm - WebAssembly Component wrapper for hello-rs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Relative path input to sibling hello-rs flake
    hello-rs.url = "path:../hello-rs";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, hello-rs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ rust-overlay.overlays.default ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Rust toolchain with wasm32-wasip2 target
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "wasm32-wasip2" ];
        };

        # Build the WASM component
        helloWasmComponent = pkgs.stdenv.mkDerivation {
          pname = "hello-wasm";
          version = "0.1.0";

          # Create source with hello-rs included
          src = pkgs.runCommand "hello-wasm-src" {} ''
            mkdir -p $out
            cp -r ${./.}/* $out/
            chmod -R +w $out
            mkdir -p $out/hello-rs
            cp -r ${../hello-rs}/* $out/hello-rs/
            # Update the Cargo.toml path to point to ./hello-rs instead of ../hello-rs
            sed -i 's|path = "../hello-rs"|path = "./hello-rs"|' $out/Cargo.toml
          '';

          cargoDeps = pkgs.rustPlatform.importCargoLock {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [
            rustToolchain
            rustPlatform.cargoSetupHook
            wasm-tools
          ];

          buildPhase = ''
            export CARGO_HOME=$(mktemp -d)
            cargo build --target wasm32-wasip2 --release
          '';

          installPhase = ''
            mkdir -p $out/lib
            cp target/wasm32-wasip2/release/hello_wasm.wasm $out/lib/

            # Note: wasm-opt doesn't support WASM components yet, only core modules
            # See: https://github.com/WebAssembly/binaryen/issues/6728
            # The component is already optimized by cargo's --release flag at the LLVM level
          '';
        };

      in
      {
        packages = {
          default = helloWasmComponent;
          hello-wasm = helloWasmComponent;
          # Re-export the Rust library from the subflake
          hello-rs = hello-rs.packages.${system}.default;
        };

        checks = {
          wasmtime-test = pkgs.stdenv.mkDerivation {
            name = "hello-wasm-wasmtime-test";
            src = ./.;

            nativeBuildInputs = with pkgs; [
              wasmtime
              jq
            ];

            buildInputs = [ helloWasmComponent ];

            buildPhase = ''
              # Set up hermetic environment for wasmtime
              export HOME=$TMPDIR
              export XDG_CACHE_HOME=$TMPDIR/.cache
              export XDG_CONFIG_HOME=$TMPDIR/.config
              mkdir -p $XDG_CACHE_HOME $XDG_CONFIG_HOME

              # Copy the built WASM component
              cp ${helloWasmComponent}/lib/hello_wasm.wasm ./

              # Create a test script that runs multiple test cases
              cat > run_tests.sh <<'TESTSCRIPT'
              #!/usr/bin/env bash
              set -e

              TOTAL=0
              PASSED=0
              FAILED=0
              TEST_RESULTS=""

              # Helper function to run a test
              run_test() {
                local test_name="$1"
                local input="$2"
                local expected="$3"

                TOTAL=$((TOTAL + 1))

                # Run wasmtime with cache disabled for hermetic builds
                # For Component Model, use simple function invocation syntax
                if output=$(wasmtime run -C cache=n --invoke 'hello("'"$input"'")' hello_wasm.wasm 2>&1); then
                  # Strip any ANSI codes and trim whitespace
                  output=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | xargs)

                  if [ "$output" = "$expected" ]; then
                    PASSED=$((PASSED + 1))
                    TEST_RESULTS="$TEST_RESULTS  [passed] $test_name\n"
                    echo "✓ $test_name: '$output'"
                  else
                    FAILED=$((FAILED + 1))
                    TEST_RESULTS="$TEST_RESULTS  [failed] $test_name (expected: '$expected', got: '$output')\n"
                    echo "✗ $test_name: expected '$expected', got '$output'"
                  fi
                else
                  FAILED=$((FAILED + 1))
                  TEST_RESULTS="$TEST_RESULTS  [failed] $test_name (wasmtime error)\n"
                  echo "✗ $test_name: wasmtime failed with: $output"
                fi
              }

              # Run test cases
              echo "Running wasmtime tests..."
              run_test "test_hello_basic" "world" "Hello World!"
              run_test "test_hello_name" "claude" "Hello Claude!"
              run_test "test_hello_multiword" "rust wasm" "Hello Rust Wasm!"

              # Print summary
              echo ""
              echo "Test Summary:"
              echo "Total: $TOTAL"
              echo "Passed: $PASSED"
              echo "Failed: $FAILED"
              echo ""
              echo "Test Results:"
              echo -e "$TEST_RESULTS"

              # Export for Nix to capture
              echo "$TOTAL" > total.txt
              echo "$PASSED" > passed.txt
              echo "$FAILED" > failed.txt
              echo -e "$TEST_RESULTS" > test-list.txt

              # Exit with failure if any tests failed
              [ $FAILED -eq 0 ]
              TESTSCRIPT

              chmod +x run_tests.sh
              ./run_tests.sh 2>&1 | tee test-output.txt
            '';

            installPhase = ''
              mkdir -p $out

              # Read test results
              TOTAL=$(cat total.txt)
              PASSED=$(cat passed.txt)
              FAILED=$(cat failed.txt)

              # Create formatted summary
              cat > $out/summary.txt <<EOF
Hello-wasm wasmtime test results:
==================================
Total: $TOTAL tests
Passed: $PASSED
Failed: $FAILED

Tests run:
$(cat test-list.txt)

EOF

              # Copy full output for debugging
              cp test-output.txt $out/full-output.txt

              # Check if tests passed
              if [ "$FAILED" -ne 0 ]; then
                echo "Tests failed!"
                exit 1
              fi
            '';

            doCheck = false;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            rustToolchain
            rust-analyzer
            clippy
            rustfmt
            wasm-tools
            wasmtime
            binaryen
          ];

          shellHook = ''
            export REPO_ROOT=$(pwd)
            unset DEVELOPER_DIR
            echo "WebAssembly Component Development Environment"
            echo ""
            echo "Build commands:"
            echo "  cargo build --target wasm32-wasip2 --release"
            echo ""
            echo "Inspect component:"
            echo "  wasm-tools component wit target/wasm32-wasip2/release/hello_wasm.wasm"
            echo ""
            echo "Optimize:"
            echo "  wasm-opt -O3 -o optimized.wasm target/wasm32-wasip2/release/hello_wasm.wasm"
          '';
        };
      });
}
