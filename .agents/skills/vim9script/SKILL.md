---
name: vim9script
description: Write, style, review, and test idiomatic typed Vim9 scripts and plugins, or port legacy Vim script to Vim9 while preserving editor behavior and public APIs.
---

# Vim9 script

Identify the minimum Vim build and the entry points users actually invoke. Check the project's tests and the target binary's `:version` and `:help`. Features such as classes, generics, and tuples arrived at different patch levels. When older interpreters must remain supported, select the implementation in a compatible loader before sourcing syntax they cannot parse.

For writing and review, apply the [Vim9 style guide](references/style.md). It covers naming, layout, control flow, strings and patterns, and how plugin code should interact with the editor. Follow established project formatting and keep public names stable across ports.

## Choose the implementation

- For new functions, data models, callbacks, or classes, use the [typed language patterns](references/language.md). Give public parameters, results, and stored collections concrete types. Let an obvious initializer supply a local's type. Use a module for related operations and a class when instances own state or enforce an invariant.
- For commands, mappings, autoload APIs, or a legacy port, follow the [module and porting guide](references/porting.md). Preserve caller-visible names, argument conventions, side effects, and error behavior across upstream updates.
- For external processes, incremental output, or cancellable editor work, use the [jobs and channels guide](references/jobs.md). Decide who owns each handle, which editor object receives updates, and what signals completion.

## Compile and exercise the result

1. Source the real entry point with the plugin on Vim's runtimepath. Sourcing registers a `def`; compilation normally happens on first use. In development, place `defcompile` **inside the defining script**, after its definitions, to find errors in uncalled functions and class methods. For a generic function, compile or invoke representative concrete specializations. Keep production startup lazy where it matters.
2. Invoke the exported API, command, mapping, or event from its actual caller context. Compilation alone misses late autoload resolution, dynamic values, option expressions, and callback timing. Check observable output, mutations, and failure paths. For ports, run equivalent scenarios against the legacy implementation and the port in separate Vim processes.
3. Run a disposable driver with `vim -Nu NONE -U NONE -i NONE -n -es -S check.vim`. Set the test runtimepath before sourcing the plugin. Finish the driver as below. Assertions accumulate in `v:errors`; an unconditional successful quit can hide failures. For silent Ex errors, rerun with `-V1vim-test.log` and inspect the first error and throwpoint.

```vim
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
```

For performance work, move repeated computation into compiled functions, batch editor operations such as multi-line buffer updates, and measure startup separately from steady-state work. Use `--startuptime` for loading, `:profile` on a build with profiling for hot functions, and `:disassemble` to inspect what a specific definition compiled to.

Use the installed help for the target build. Online references include the [language manual](https://vimhelp.org/vim9.txt.html), [class manual](https://vimhelp.org/vim9class.txt.html), and [sourceable syntax primer](https://learnxinyminutes.com/vim9script/).
