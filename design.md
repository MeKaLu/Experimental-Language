# Design

```javascript

# comments
# "almost everything" is an expression
# every expression must return a value
# if an expression returns void, it can be implicitly discarded
# void is a special construct, it has an immutable value
#   and can be accessed with void:default.
#   Every type has void inside of them, and their uninitialized
#   values are void:default.
# every expression can be used in a statement
# every statement must end with ;

let io := "std::io" @import;
usenamespace := "std::str::tostr" @import;

# returns a type with the following values and methods defined
let Animals := @(new_type = true) {
  # because these are immutable, compiler can assign them
  # unique values
  let Dog;
  let Cat;
  let Bird;
  let Human;
  let Bear;
};

let entry_point := @(entry_point = true) {
  {
    let foo := "foo";
    foo "Foo = {}" $io:println;
  };

  {
    let int := 10;
    let other_int := i32(10);
    int == other_int @assert;
  };
  
  let me: Animals = Human;
  let bessy := Animals:Dog;

  # because this can return multiple types of values
  # the type must be checked before attempting to use the value
  let value := {
    let svalue := switch me {
      # {} implicitly returns void
      | Dog   = {};
      | Cat   = {};
      | Bird  = {};
      | Human = return := 10;
      # all of the switch cases must be handled
      # others
      || = {};
    };
    return := if svalue == void:default @panic("Expected value got void"); else svalue;
  };
  
  # Unions
  {
    # if a "member" of the type contains a type, it becomes a "typed type member"
    # you can assign a value and access
    # if it is tagged, anything other than "typed type member" is void:default,
    # thus in a switch statement, they are skipped
    # otherwise its a C union
    let Union := @(new_type = true; tagged = true) {
      let as_int := i32;
      let as_bool := bool;
      let as_float := f32;
      
      let mut mutable_member: u8 = 20;
    };
    
    let foo := Union:as_int(5);
    10 foo.mutable_member @set;
    (foo.mutable_member == 10) @assert;

    # If it was tagged
    # it only switchs tagged types and on "typed type member"s
    switch foo {
      | as_int(captured) = (captured == 5) @assert;
      | as_bool(captured) | as_float(captured) = "this should be skipped bc there is no value in captured" @panic;
      # all of the switch cases are handled
    };

    # if it was NOT tagged
    # you cannot switch on non-tagged types
    (foo.as_int() == 5) @assert;
    (foo.as_bool() != void:default) @assert;
    (foo.as_float() != void:default) @assert;

    # Optional types:
    {
      let Option := (T: type) @(new_type = true; tagged = true) {
        let nothing := void:default;
        let some    := T;
      };

      let foo := switch me {
        | Human = return := (i32 Option):some(10);
        # because :nothing is immutable, and does not depend on T
        # we can just use it as is
        || = return := Option:nothing;
      };

      # if it DID contained something
      (foo.nothing() == void:default) @assert;
      (foo.some() == 10) @assert;

      # if it did NOT contained something
      (foo.nothing() == void:default) @assert;
      (foo.some() == void:default) @assert;
    };
  };
  

  loop {
    break;  
  };

  if cond {
    
  } else if cond {
    
  } else {
    
  };

  genericAdd:pure @assert;

  # syntax sugar: "discard := {"
  {
    let mut a, mut b: i32, i32;
    10 a @set;
    20 b @set;

    let c := a b @add;
    c == 30 @assert
  };

  {
    # to make a tuple, you just need to put at least
    # 2 things in sequence:
    
    # type is "i32; i32"
    let tuple := 10 10;
    # "mut i32; mut i32"
    let mut_tuple := (mut 10) (mut 10);
    # "a: i32; b: i32"
    let named_tuple := (a := 10) (b := 10);
    # "mut a: f32; b: i32"
    let named_tuple2 := (mut a: f32 = 0.5) (b := 10);
    # syntax sugar for: "a: i32; b: i32"
    let named_tuple3: a, b: i32 = (.a = 10) (.b = 20);
  };

  {
    # returns a unique named tuple with: "mut x: T; mut y: T"
    # and has a method called "add"
    # although this is allowed by the nature of the language
    # its not really "the correct" way to create a "struct"
    let Vec2 := (px, py := T:default; T: type) {
      let mut x := px;
      let mut y := py;

      # @This here returns "(mut x, mut y: T)"
      let add := (v0, v1: @This) @This @(pure = true) {
        return: @This = (v0.x v1.x @add) (v0.y v1.y @add);
      };
    };
    # mut x: i32; mut y: i32
    ((i32 $Vec2) == unique_named_tuple_i32_Vec2) @assert;

    let position: (i32 $Vec2) = (.x = 10) (.y = 10);
    let offset:   (i32 $Vec2) = (.x = 20) (.y = 0);
    # px and py here is i32:default,
    # and the syntax is expanded like this:
    # let offseted_pos: mut a, mut b: i32 = (.a = i32:default) (.b = i32:default);
    let offseted_pos: (i32 $Vec2);

    ((i32 $Vec2) == (position @type)) @assert;

    -10 offset.y @set;
    position offset ((i32 $Vec2):add) offseted_pos @set;
  };

  {
    # returns a new type
    # "the correct" way to create a struct
    let Vec2 := (px, py := T:default; T: type) @(new_type = true) {
      let mut x := px;
      let mut y := py;
      
      # @This here returns a completely unique type
      let add := (v0, v1: @This) @This @(pure = true) {
        return := .(
          .x = (v0.x v1.x @add);
          .y = (v0.y v1.y @add);
        );
        # or
        return := @This(
          .x = (v0.x v1.x @add);
          .y = (v0.y v1.y @add);
        );
      };
    };
    
    let position := (i32 Vec2)(.x = 10, .y = 10);
    let offset   := (i32 Vec2)(.x = 20, .y = 0);
    let offseted_pos: (i32 Vec2);

    ((i32 Vec2) == (position @type)) @assert;

    -10 offset.y @set;
    position offset $Vec2:add offseted_pos @set;
  };

  let mut ownmemory: [1024]u8 = loop {
    let i: u32 = 0;
    defer := 1 i @add;

    if i >= @This:len break;
    0 @This[i] @set;
  };

  let mut ownmemory: ptr u8 = 1024 $alloc;
  defer := ownmemory $free

  @(memory = ownmemory) {
    let a, b := (10 i32 @cast), 20;
    let c := a b @add $tostr;
    c "a + b = {}" $io:println;
  };
}

let generic_add := (a, b: anytype) (a @type) @(pure = true) {
  @(comptime = true) {
    if (a @type) != (b @type) {
      "types must be the same!" @compile_error;
    };
  };

  return := a b @add;
};

```
