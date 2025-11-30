# Hello Subflakes

As far as I can tell "nix subflake" is not a well defined term.
What I mean here is:

> A nix flake whose `(great)*(grand)?parent` directory is also a flake

Subflakes behavior was [improved as of nix 2.4](https://github.com/NixOS/nix/pull/10089) (Feburary 2024).
Here I'm exploring how they can be useful.

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

## Local Remotes

I'm not a fan of monorepo's generally, but if I've bundled some subflakes together by nesting them under a parent flake, it's because:

- Either the subflake outputs are intermediate artifacts and are not re-exported for user consumption as outpts of the parent flake
- or they are also outputs of the parent flake, but they're to be released with the same version number.

However, in development, I still want to be able to use git to vary one subflake while keeping another at a fixed commit.
e.g. I want to be able to `git bisect` only one subflake.
For this reason the subflake repositories are not remote but included in the parent flake.

TODO: subtrees don't actually allow for `git bisect`, but maybe you can at least alter the flake input to get a version of that subtree from the past?

So my strategy is to create repositories in `./subflake-git` like `git init --bare` and then use them as the "remote" for a git subtree around each flake.
But they're just in the parent directory, so they're not actually remote at all.

Setting up a new subflake goes something like this.
Once I settle on a flow I may make a `subflake add` command 

```
# create empty local remote
mkdir subflake-git/hello-foo
cd subflake-git/hello-foo
git init --bare --initial-branch=main
cd ../..

# the git subflake command dislikes empty remotes
# so we'll clone it and populate it
git clone subflake-git/hello-foo
cd hello-foo
nix flake init
git add . ; git commit -m "initial commit" ; git push origin main

# remote the clone and add it back as a subtree
cd ..
rm -rf hello-foo
git subtree add --prefix hello-foo subflake-git/hello-foo main
```

I'm not sure if this is a good idea yet, trying it out...

## Warnings

#### AI Disclaimer
Although I believe that my tests prove the concept reasonably well, there's a lot of LLM-generated code here.
Think twice before assuming that you're not looking at insanity.

#### Experimental
I've been using it for about an hour so far.
It seems like a workable arrangement, but I'm sure there are undiscovered gotchas.
I'll try to document them here as I explore.

#### Cache Complexity
Since each subflake has its own `flake.lock` it may be necessary to run `nix flake update {some-subflake}` more often than you'd expect.
I've not decided if this is a bug or a feature.

#### Absolute Paths
This issue makes it awkward to use relative paths to indicate the local git repo's: https://github.com/NixOS/nix/issues/12281
Until it is fixed, these flakes are using absolute paths: `git:file:///Users/matt/src/hello-subflake/subflake-git`
