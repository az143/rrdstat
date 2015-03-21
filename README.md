this repository contains `rrdstat`, a standalone/non-snmp data
gatherer for collection in rrd database files, and `mrrd`, a tiny 
mojolicious web app to display the resulting graphs.

the system is documented on my site at
[http://snafu.priv.at/mystuff/rrdstat.html](http://snafu.priv.at/mystuff/rrdstat.html),
but you will likely still have to do a bit UTSL! to get everything
adjusted for your needs.

the most relevant files for this purpose: 
* the example config files in `/config`
* the rrdstat gatherer script in `/script`
* and the `Mrrd.pm` mojolicious app class in `/lib`

all code is (c) 2010-1025 Alexander Zangerl <az@snafu.priv.at>,
and is free and open-source software, licensed under the GPL Version 2.

share and enjoy `:-)`
