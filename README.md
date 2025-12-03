# Hello Subflakes

By "subflake" I mean:

> A nix flake whose `(great)*(grand)?parent` directory is also a flake

Subflakes behavior was [improved as of nix 2.4](https://github.com/NixOS/nix/pull/10089) (Feburary 2024).
Here I'm exploring how they can be useful.

This README is focused on what I managed to make it do.
For a simplified example describing **why** you might want to arrange your code like this, see [this gist](https://gist.github.com/MatrixManAtYrService/6eaf50373448c0bc14acca31d69591b9)


## Outer/Parent/Super Flake Functionality

You're looking at the README for the outer flake.
It provides a CLI app called "hello-fancy".

```
❯ hello-fancy world
Hello World! 
```

The fancy part is that it's uppercase with a bang! 🧐

Unlike your typical hello-world, "world" was appended to "hello" by...

- a rust library (`hello-rs` subflake),
- which was embedded in a python library (`hello-py` subflake),
- which was imported by a python application (outer flake, `hello-fancy` app).


There's also a flake output `hello-web` which does something similar in a browser:

```
❯ nix build .#hello-web
❯ python -m http.server --directory result
Serving HTTP on :: port 8000 (http://[::]:8000/) ...
```
![screenshot of a web browser, a button click has transformed "world" into "Hello World!"](./hello-web.png)

In this case "world" was appended to "hello" by...
- a rust library (`hello-rs` subflake),
- which was compiled to a WASM [component](https://component-model.bytecodealliance.org/) (`hello-wasm` subflake),
- which was transpiled and set up for browser use (`hello-web` subflake).

So in addition to makeing a complex DAG out of flake-based projects, those projects can themselve be a complex DAG of dependencies.
What fun!

## Outer/Parent/Super Flake Testing of Subflakes

You can also run `pytest` from the outer devshell:
```
❯ pytest -v
============================ test session starts =============================
tests/test_hello_py.py::test_hello_py_pytest_check PASSED              [ 11%]
tests/test_hello_py.py::test_hello_py_import_smoke_test PASSED         [ 22%]
tests/test_hello_rs.py::test_hello_rs_cargo_test_check PASSED          [ 33%]
tests/test_hello_rs.py::test_hello_rs_library_smoke_test PASSED        [ 44%]
tests/test_hello_wasm.py::test_hello_wasm_wasmtime_check PASSED        [ 55%]
tests/test_hello_wasm.py::test_hello_wasm_component_smoke_test PASSED  [ 66%]
tests/test_hello_web.py::test_hello_world_greeting PASSED              [ 77%]
tests/test_hello_web.py::test_empty_input_validation PASSED            [ 88%]
tests/test_hello_web.py::test_multiple_names PASSED                    [100%]
============================= 9 passed in 10.00s =============================
```

This integrates with the subflakes in a variety of ways.
The idea is that each subflake can test itself according to whatever is idiomatic for the code contained therein, and here at the top level we can just extract results--relying on nix to give us cached results (and to invalidate that cache appropriately).

I put python at the top level just because it is most familliar for me.

## It's about Ignorance

When I'm working at the top level I want to be able to **ignore** the tech stacks of each subflake, more or less just operating on their outputs and relying on nix to cach or rebuild those outputs as appropriate.
Similarly, when I'm working in a subflake I want to be able to ignore the bigger picture, focusing only on that flake's outputs.

For this reason `cargo` and `wasmtime` are not available in the outer flake devshell, and `python` and `pytest` are not available in (most of the) inner flake devshells.
There are multiple python environments, but they're isolated to different flakes, so for better or worse we're well prepared to depend on different versions of the same python package in different parts of our project.

I anticipate that this context-limiting will be useful for preventing LLMs being dazzled by multiple overlapping tech stacks.
I may have been similarly dazzled once or twice myself.

I also think it creates interesting opportunities for making conglomerations of heterogeneous technology feel like a single thing.
Which might be good or bad, depending on how you feel about remixes.

## Subflakes

```
├── hello-rs/          # Core Rust library
├── hello-py/          # Python bindings (PyO3/Maturin)
├── hello-wasm/        # WebAssembly Component (WASI 0.2)
└── hello-web/         # Browser application
```

## Warnings

#### AI Disclaimer
Although I believe that my tests prove the concept reasonably well, there's a lot of LLM-generated code here.
Think twice before assuming that you're not looking at insanity.

#### Experimental
It seems like a workable arrangement, but I'm sure there are undiscovered gotchas.
I'll try to document them here as I explore.

#### Cache Complexity
Since each subflake has its own `flake.lock` it may be necessary to run `nix flake update` more often than you'd expect.
I've not decided if this is a bug or a feature.
