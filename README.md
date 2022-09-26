# nvim-treesitter-dart-data-class

Neovim plugin to generate toString, hashCode, and equals for Dart data classes.

## What does this do?

Using this plugin you get a command that when run when the cursor is inside a Dart class, generates `toString`, `hashCode`, and `==` (equals in Java) like in this example:

```dart
class Person {
  final String name;
  final int age;
  final Map<String, Person> relatives;

  Person(this.name, this.age, this.relatives);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Person &&
          other.name == name &&
          other.age == age &&
          other.relatives == relatives;

  @override
  int get hashCode => name.hashCode + age.hashCode + relatives.hashCode;

  @override
  String toString() => 'Person[name=$name, age=$age, relatives=$relatives]';
}
```

The minimum you have to have is a class with fields, but this plugin won't generate constructors for you.

### Features

- Generate `toString`, `hashCode`, and `==`
- Update `toString`, `hashCode`, and `==` if they exist

### Limitations

- I didn't really care to write error handling that much, so if you use the command when it's not applicable, you'll see ugly Neovim errors with traces and such.
- Generation also automatically formats your file with LSP. Open an issue, if you need this changed in some way (e.g. configurable to be turned off, or format only the generated parts)

## Installation

```lua
--- With packer.nvim
use 'TamasBarta/nvim-treesitter-dart-data-class'
```

## Usage

1. Move the cursor over/inside a class
2. Run `:lua require"nvim-treesitter-dart-data-class".generate()`

