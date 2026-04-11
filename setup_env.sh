# install ghosty
snap install ghostty --classic

# install zsh
apt install zsh
chsh -s $(which zsh)

# install starship
curl -sS https://starship.rs/install.sh | sh
echo "$(starship init zsh)" >> ~/.zshrc

# eza
apt install eza

echo "alias ld='eza -lD'" >> ~/.zshrc
echo "alias lf='eza -lF --color=always | grep -v /'" >> ~/.zshrc
echo "alias lh='eza -dl .* --group-directories-first'" >> ~/.zshrc
echo "alias ll='eza -al --group-directories-first'" >> ~/.zshrc
echo "alias ls='eza -alF --color=always --sort=size | grep -v /'" >> ~/.zshrc
echo "alias lt='eza -al --sort=modified'" >> ~/.zshrc
