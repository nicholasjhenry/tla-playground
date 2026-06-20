defmodule TlaPlaygroundTest do
  use ExUnit.Case
  doctest TlaPlayground

  test "greets the world" do
    assert TlaPlayground.hello() == :world
  end
end
