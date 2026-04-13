# install ghosty
snap install ghostty --classic

# install zsh
apt install zsh
chsh -s $(which zsh) $USER

# install starship
curl -sS https://starship.rs/install.sh | sh
echo "$(starship init zsh)" >> ~/.zshrc

# eza
apt install eza

echo "alias lh='eza -al --group-directories-first'" >> ~/.zshrc
echo "alias ll='eza -l --group-directories-first'" >> ~/.zshrc
echo "alias ls='eza -lF --color=always --sort=size | grep -v /'" >> ./zshrc
