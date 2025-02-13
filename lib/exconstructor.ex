defmodule ExConstructor do
  @moduledoc ~s"""
  ExConstructor is an Elixir library that makes it easy to instantiate
  structs from external data, such as that emitted by a JSON parser.

  Add `use ExConstructor` after a `defstruct` statement to inject
  a constructor function into the module.

  The generated constructor, called `new` by default,
  handles map-vs-keyword-list, string-vs-atom-keys, and
  camelCase-vs-under_score input data issues automatically,
  DRYing up your code and letting you move on to the interesting
  parts of your program.

  ## Installation

  1. Add ExConstructor to your list of dependencies in `mix.exs`:

          def deps do
            [{:exconstructor, "~> #{ExConstructor.Mixfile.project[:version]}"}]
          end

  2. Ensure ExConstructor is started before your application:

          def application do
            [applications: [:exconstructor]]
          end

  ## Usage

  Example:

      defmodule TestStruct do
        defstruct field_one: 1,
                  field_two: 2,
                  field_three: 3,
                  field_four: 4,
        use ExConstructor
      end

      TestStruct.new(%{"field_one" => "a", "fieldTwo" => "b", :field_three => "c", :FieldFour => "d"})
      # => %TestStruct{field_one: "a", field_two: "b", field_three: "c", field_four: "d"}

  For advanced usage, see `__using__/1` and `populate_struct/3`.

  ## Authorship and License

  ExConstructor is copyright 2016-2017 Appcues, Inc.

  ExConstructor is released under the
  [MIT License](https://github.com/appcues/exconstructor/blob/master/LICENSE.txt).
  """

  @type map_or_kwlist :: %{String.t => any}|%{atom => any}|[{String.t, any}]|[{atom, any}]

  defmodule Options do
    @moduledoc ~S"""
    Represents the options passed to `populate_struct/3`.
    Set any value to `false` to disable checking for that kind of key.
    """
    defstruct strings: true,
              atoms: true,
              camelcase: true,
              uppercamelcase: true,
              underscore: true
  end


  @doc ~S"""
  `use ExConstructor` defines a constructor for the current module's
  struct.

  If `name_or_opts` is an atom, it will be used as the constructor name.
  If `name_or_opts` is a keyword list, `name_or_opts[:name]` will be
  used as the constructor name.
  By default, `:new` is used.

  Additional options in `name_or_opts` are stored in the
  `@exconstructor_default_options` module attribute.

  The constructor is implemented in terms of `populate_struct/3`.
  It accepts a map or keyword list of keys and values `map_or_kwlist`,
  and an optional `opts` keyword list.

  Keys of `map_or_kwlist` may be strings or atoms, in camelCase or
  under_score format.

  `opts` may contain keys `strings`, `atoms`, `camelcase` and `underscore`.
  Set these keys false to prevent testing of that key format in
  `map_or_kwlist`.  All default to `true`.

  For the default name `:new`, the constructor's definition looks like:

      @spec new(ExConstructor.map_or_kwlist, Keyword.t) :: %__MODULE__{}
      def new(map_or_kwlist, opts \\ []) do
        ExConstructor.populate_struct(%__MODULE__{}, map_or_kwlist, Keyword.merge(@exconstructor_default_options, opts))
      end
      defoverridable [new: 1, new: 2]

  Overriding `new/2` is allowed; the generated function can be called by
  `super`.  Example uses include implementing your own `opts` handling.
  """
  defmacro __using__(name_or_opts \\ :new) do
    opts = cond do
             is_atom(name_or_opts) -> [name: name_or_opts]
             is_list(name_or_opts) -> name_or_opts
             true -> raise "argument must be atom (constructor name) or keyword list (opts)"
           end
    constructor_name = opts[:name] || :new

    quote do
      @exconstructor_default_options unquote(opts)
      @spec unquote(constructor_name)(ExConstructor.map_or_kwlist, Keyword.t) :: %__MODULE__{}
      def unquote(constructor_name)(map_or_kwlist, opts \\ []) do
        ExConstructor.populate_struct(
          %__MODULE__{},
          map_or_kwlist,
          Keyword.merge(@exconstructor_default_options, opts)
        )
      end
      defoverridable [{unquote(constructor_name), 1}, {unquote(constructor_name), 2}]
    end
  end

  @doc "Alias for `__using__`, for those who prefer an explicit invocation."
  defmacro define_constructor(name_or_opts \\ :new) do
    quote do: ExConstructor.__using__(unquote(name_or_opts))
  end

  @doc ~S"""
  Returns a copy of `struct` into which the values in `map_or_kwlist`
  have been applied.

  Keys of `map_or_kwlist` may be strings or atoms, in camelCase,
  UpperCamelCase, or under_score format.

  `opts` may contain keys `strings`, `atoms`, `camelcase`, `uppercamelcase`,
  and `underscore`.
  Set these keys false to prevent testing of that key format in
  `map_or_kwlist`.  All default to `true`.
  """
  @spec populate_struct(struct, map_or_kwlist, %Options{}) :: struct
  def populate_struct(struct, map_or_kwlist, %Options{}=opts) do
    map = cond do
            is_map(map_or_kwlist) -> map_or_kwlist
            is_list(map_or_kwlist) -> Enum.into(map_or_kwlist, %{})
            true -> raise "second argument must be a map or keyword list"
          end
    keys = case struct do
      %{__struct__: _t} -> (struct |> :maps.keys) -- [:__struct__]
      _ -> raise "first argument must be a struct"
    end
    Enum.reduce keys, struct, fn (atom, acc) ->
      str = to_string(atom)
      value = cond do
        Map.has_key?(map, str) and opts.strings ->
          Map.get(map, str)
        Map.has_key?(map, atom) and opts.atoms ->
          Map.get(map, atom)
        true ->
          Map.get(struct, atom)
      end
      Map.put(acc, atom, value)
    end
  end

  @spec populate_struct(struct, map_or_kwlist, map_or_kwlist) :: struct
  def populate_struct(struct, map_or_kwlist, opts) do
    opts_struct = populate_struct(%Options{}, opts, %Options{})
    populate_struct(struct, map_or_kwlist, opts_struct)
  end

  @doc ~S"""
  Returns a copy of `struct` into which the values in `map_or_kwlist`
  have been applied.

  Keys of `map_or_kwlist` may be strings or atoms, in camelCase or
  under_score format.
  """
  @spec populate_struct(struct, map_or_kwlist) :: struct
  def populate_struct(struct, map_or_kwlist) do
    populate_struct(struct, map_or_kwlist, %Options{})
  end


  ## Returns `str` with its first character lowercased.
  @spec lcfirst(String.t) :: String.t
  def lcfirst(<<x::bytes-size(1), rest::binary>>) do
    String.downcase(x) <> rest
  end

end
