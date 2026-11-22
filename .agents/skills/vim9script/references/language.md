# Typed functions and data

Start a Vim9 module with `vim9script` as its first command. Use `#` for comments after that line. Write `name: type`, spaces around binary operators and assignments, a space after commas, and no space before a call's opening parenthesis. Continue expressions inside open delimiters. Indent multiline calls and dictionary literals to make their structure visible.

Use `def Name(...)` / `enddef`. Ordinary named functions start with a capital letter. Omit the return annotation for a procedure or spell it `: void`. Use a default such as `limit: number = 10` to express an optional argument, and `...names: list<string>` for homogeneous extra arguments. Arguments have final bindings. Decide whether mutating a caller's list or dictionary is part of the contract.

```vim
vim9script

def SelectNames(names: list<string>, Accept: func(string): bool): list<string>
  final selected: list<string> = []
  for name in names
    if Accept(name)
      selected->add(name)
    endif
  endfor
  return selected
enddef

const prefix = 'doc/'
assert_equal(['doc/tags'], SelectNames(['doc/tags', 'tags'],
    (name: string): bool => stridx(name, prefix) == 0))
```

- Use `var` for rebinding, `final` for a stable binding whose contents may change, and `const` for locked data. Locking shared containers can affect other holders of the same value. Assignment aliases a list or dictionary. Use `copy()` for an independent outer container and `deepcopy()` when nested mutation must be isolated.
- Use `list<T>` for a sequence, `dict<T>` for string keys with one value type, and, where supported, `tuple<T, U>` for a fixed positional result. Give empty accumulators their element type. A `type` alias gives a long type a name. For heterogeneous records with named fields and invariants, consider a class.
- Treat options dictionaries, decoded JSON, and legacy function returns as boundaries. Check the outer kind with `type()`, required keys with `has_key()`, and the kinds of their values before constructing typed internal data. A cast such as `<string>value` asserts a type. For a numeric string, validate the accepted format and convert with `str2nr()`. Use `any` at an open boundary only as far as the data genuinely varies.
- Use a typed Funcref parameter for an operation supplied by the caller. Match the invoking API's arity. For a list, `mapnew((_, value) => ...)` receives both index and value and returns a new collection. `map()`, `filter()`, and `sort()` change their input. Use `mapnew()` when changing element type. A short lambda can capture surrounding variables. Give branching or reused callbacks a named `def`. Use a loop for early exit or when intermediate collections dominate the work.
- Where supported, preserve the relationship between input and return types with a generic function. For example, `def LastOr<T>(xs: list<T>, fallback: T): T` can return `empty(xs) ? fallback : xs[-1]`. Call it as `LastOr<string>(names, '')`. Test concrete specializations that exercise the operations on `T`.

## Objects with a small contract

```vim
vim9script

interface LineSink
  def Put(line: string)
endinterface

class Transcript implements LineSink
  var _lines: list<string> = []

  def Put(line: string)
    this._lines->add(line)
  enddef

  def Snapshot(): list<string>
    return copy(this._lines)
  enddef
endclass

def EmitHeader(sink: LineSink)
  sink.Put('Results')
enddef

final transcript = Transcript.new()
EmitHeader(transcript)
assert_equal(['Results'], transcript.Snapshot())
```

Define classes and interfaces at script scope. An ordinary instance field permits external reading. A leading underscore protects a field or method for the class and its subclasses. Use `public var` only when clients are meant to assign the field. Exposing a mutable container also exposes its contents. The snapshot above copies a list of immutable strings.

Use an explicit `def new(...)` to validate construction or stabilize the constructor API. A generated constructor can expose member order and protected members as parameters. Use `static` for state or operations shared by all instances. A declaration such as `class Child extends Parent` inherits from one base class. A class may also implement multiple interfaces. Use an abstract class for shared implementation and `abstract def` for required behavior. An interface is useful when callers need substitutable implementations such as a buffer writer and a test sink.

Where supported, use an `enum` for closed states whose identity matters. Keep serialized names or legacy numeric codes explicit when external callers depend on them since enum ordinals follow declaration order. Keep Vim9 objects behind a Vim9 boundary when supporting legacy consumers.

See the [type and function reference](https://vimhelp.org/vim9.txt.html) and [class, interface, and enum reference](https://vimhelp.org/vim9class.txt.html).
