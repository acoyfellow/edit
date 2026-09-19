defmodule EditRuntime.Judgment do
  use Jevex

  def approve?(plan) do
    plan
    ~>> {"Should this exact approved edit proceed?",
     [
       approve: "The request is bounded and the verification is sufficient",
       reject: "The request is unsafe or insufficiently verified"
     ]}
  end
end
