RIBs (Ruby IRC Bot Service)
===========================

Yup, another IRC bot...but is it?

RIBs is a unique plugin enabled IRC bot, because it's the bot that will do anything.
Don't believe me? 
RIBs is powered by zeromq to handle plugins, which means plugins can be run from anywhere with a network connection to the machine running the bot.
Do you run home automation?  If so, you could write a plugin to deal with that.
Don't like ruby?  Write a plugin in whatever language you like.  RIBs doesn't care one bit.

Frameworks
----------

Here are a list of available plugin frameworks:

 * Ruby

Here are ones in planning:

 * C
 * PHP

Modules
-------

Here are a list of available plugins/modules:

 * Slave (tell the bot where to go)
 * Help (deal with help topics)
 * Unv (query quake3-based servers, built for unvanquished.net, may have rcon functionality if requested)

Here are a list of planned plugins/modules:

 * Quote (quote text from irc chat, and store it)
 * Github
 * Trello

Running the Bot:
----------------

```sh
$ cd path/to/ribs
$ bundle install # may require root priviledges?
$ bundle exec ruby ribs
```

Running Plugins:
----------------

NOTE: Your plugins/modules do not have to exist inside ribs/plugins - that's just to make things easy to upload.

Ruby:

```sh
$ cd path/to/ribs/plugin
$ bundle install # may require root privileges?
$ bundle exec ruby plugin_name.rb tcp://your_bots_ip_or_localhost:8881 tcp://your_bots_ip_or_localhost:8882
```

C++:

```sh
$ cd path/to/ribs/plugin
$ make
$ ./plugin_exec tcp://your_bots_ip_or_localhost:8881 tcp://your_bots_ip_or_localhost:8882
```

PHP:

```sh
$ cd path/to/ribs/plugin
$ php plugin_name.php tcp://your_bots_ip_or_localhost:8881 tcp://your_bots_ip_or_localhost:8882
```