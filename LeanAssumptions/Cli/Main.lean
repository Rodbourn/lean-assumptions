import LeanAssumptions.Cli

/-!
Executable entry point for the `lean-assumptions` CLI.
-/

/-- Forward process arguments to the CLI support layer. -/
def main (args : List String) : IO UInt32 :=
  LeanAssumptions.Cli.run args.toArray
