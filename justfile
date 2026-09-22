set quiet := true

[private]
default:
  just --list --unsorted

# open nvim with only worktrunk.nvim loaded (no user config)
minimal *args:
  nvim --clean -u tests/minimal.lua {{ args }}

# run the test suite in an isolated nvim
test:
  nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
