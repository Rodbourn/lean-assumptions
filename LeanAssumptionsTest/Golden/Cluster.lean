import LeanAssumptions.Cluster
import LeanAssumptionsTest.TestUtil

/-!
Golden tests for stable failure clustering.

These tests specify the FR-017 support-layer contract before the clustering
implementation. Cluster mode consumes rendered JSON artifacts and does not
re-enter the trusted classification core.
-/

open LeanAssumptionsTest

private def clusterInputPath : System.FilePath :=
  "LeanAssumptionsTest/Golden/cluster-input.json"

run_cmd do
  let report ← LeanAssumptions.Cluster.readClusterReport clusterInputPath
  assertEq "cluster count" 3 report.summary.clusters
  assertEq "cluster failing declarations" 4 report.summary.failingDeclarations
  assertEq "cluster failure findings" 4 report.summary.failureFindings
  let first ← requireAt "first failure cluster" report.clusters 0
  assertEq "first cluster source" "package" first.key.sourceClass
  assertEq "first cluster declaration count" 2 first.declarations.size

run_cmd do
  let report ← LeanAssumptions.Cluster.readClusterReport clusterInputPath
  let actual := LeanAssumptions.Cluster.renderText report
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/cluster-report.txt"
  assertEq "cluster text golden" expected actual

run_cmd do
  let report ← LeanAssumptions.Cluster.readClusterReport clusterInputPath
  let actual := LeanAssumptions.Cluster.renderJsonString report
  let expected ← IO.FS.readFile "LeanAssumptionsTest/Golden/cluster-report.json"
  assertEq "cluster JSON golden" expected actual
