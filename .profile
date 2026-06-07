if [ -f "/etc/dotnet/install_location" ]; then
    DOTNET_ROOT="$(cat /etc/dotnet/install_location)"
    export DOTNET_ROOT
else
    export DOTNET_ROOT="$HOME/.dotnet"
fi
export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"

if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
