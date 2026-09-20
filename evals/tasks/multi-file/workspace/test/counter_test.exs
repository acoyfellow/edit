defmodule CounterTest do
  use ExUnit.Case
  test "next", do: assert Counter.next(1) == 2
end
