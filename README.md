keineSchweine
========================
Just a dumb little game

### Dependencies

* Nimrod 0.8.15, until this version is released I'm working off Nimrod HEAD
* SFML 2.0 (git), same for SFML and CSFML 
* CSFML 2.0 (git)
* Chipmunk 6.1.1

### How to build?

* `git clone git://github.com/fowlmouth/keineSchweine.git somedir`
* `cd somedir`
* `git submodule init`
* `git submodule update`
* `nimrod c -r keineschweine` or `nimrod c -r nakefile test`

### Download the game data

You need to download the game data before you can play:
http://dl.dropbox.com/u/37533467/data-08-01-2012.7z

Unpack it to the root directory. You can use the nakefile to do this easily: 

* `nimrod c -r nakefile`
* `./nakefile download`
