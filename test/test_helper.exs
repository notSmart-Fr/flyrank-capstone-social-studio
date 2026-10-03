ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(FlyrankCapstoneSocialStudio.Repo, :manual)
# Ensure Bypass application is started for HTTP testing
Application.ensure_all_started(:bypass)
