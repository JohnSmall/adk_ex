defmodule ADK.Tool.LoadArtifactsTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Artifact.InMemory, as: ArtifactService
  alias ADK.Session
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Tool.LoadArtifacts
  alias ADK.Types.Part

  defp setup_artifact do
    name = :"la_art_#{System.unique_integer([:positive])}"
    prefix = :"la_artp_#{System.unique_integer([:positive])}"
    {:ok, pid} = ArtifactService.start_link(name: name, table_prefix: prefix)
    pid
  end

  defp make_tool_ctx(artifact_server) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}}

    ctx = %InvocationContext{
      session: session,
      artifact_service: artifact_server
    }

    cb_ctx = CallbackContext.new(ctx)
    ToolContext.new(cb_ctx, "call_1")
  end

  test "loads existing artifacts" do
    art = setup_artifact()

    ArtifactService.save(art,
      app_name: "test",
      user_id: "u1",
      session_id: "s1",
      filename: "notes.txt",
      part: Part.new_text("my notes")
    )

    tool_ctx = make_tool_ctx(art)
    tool = %LoadArtifacts{}

    {:ok, result} = LoadArtifacts.run(tool, tool_ctx, %{"artifact_names" => ["notes.txt"]})
    assert length(result["artifacts"]) == 1
    assert hd(result["artifacts"])["content"] == "my notes"
  end

  test "returns error for missing artifacts" do
    art = setup_artifact()
    tool_ctx = make_tool_ctx(art)
    tool = %LoadArtifacts{}

    {:ok, result} = LoadArtifacts.run(tool, tool_ctx, %{"artifact_names" => ["missing.txt"]})
    assert hd(result["artifacts"])["error"] == "not_found"
  end

  test "loads multiple artifacts" do
    art = setup_artifact()

    ArtifactService.save(art, app_name: "test", user_id: "u1", session_id: "s1", filename: "a.txt", part: Part.new_text("aaa"))

    ArtifactService.save(art, app_name: "test", user_id: "u1", session_id: "s1", filename: "b.txt", part: Part.new_text("bbb"))

    tool_ctx = make_tool_ctx(art)
    tool = %LoadArtifacts{}

    {:ok, result} = LoadArtifacts.run(tool, tool_ctx, %{"artifact_names" => ["a.txt", "b.txt"]})
    contents = Enum.map(result["artifacts"], & &1["content"])
    assert "aaa" in contents
    assert "bbb" in contents
  end

  test "declaration has correct structure" do
    tool = %LoadArtifacts{}
    decl = LoadArtifacts.declaration(tool)
    assert decl["name"] == "load_artifacts"
    assert decl["parameters"]["properties"]["artifact_names"]["type"] == "array"
  end
end
