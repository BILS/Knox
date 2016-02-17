Customizing the dashbaord
=========================

It is not very useful to following the customizing guide from the
installation guide, since it won't work!  The following solution is
based on
[the horizon developer documentation](http://docs.openstack.org/developer/horizon/topics/customizing.html).


We first set the `CUSTOM_THEME_PATH` variable in
`/etc/openstack-dashboard/local_settings` to be
`/etc/openstack-dashboard/knox`. This will be the theme folder.

If the theme folder contains a subfolder called `static`, then the
images in that folder will take precedence on the ones from
`/usr/share/openstack-dashboard/static/`. Therefore, we copy the
following logo to `/etc/openstack-dashboard/knox/static/img/`.

![Knox Logo](/img/logo.png)


Moreover, a theme must contain <code class=special>_variables.scss</code> and
<code class=special>_styles.scss</code>.

~~~~{.css}
cat > /etc/openstack-dashboard/knox/static/_variables.scss <<EOF
@import "../themes/default/variables";
\$webroot = "/" !default;
EOF
~~~~

~~~~{.css}
cat > /etc/openstack-dashboard/knox/static/_styles.scss <<EOF
@import "../themes/default/styles";

#splash .login { background-size: 80%; /* contain */ }
EOF
~~~~

Finally, by restarting `httpd`, we get the updated <code
class=special>Horizon</code>.  Inspired from
`/usr/lib/systemd/system/httpd.service.d/openstack-dashboard.conf`, we
can also first test the theme with

	/usr/bin/python /usr/share/openstack-dashboard/manage.py collectstatic --noinput --clear
	/usr/bin/python /usr/share/openstack-dashboard/manage.py compress --force

Be careful, if the previous commands fail, the `httpd` server won't
start, and neither will `keystone`.

- - - 
Frédéric Haziza <daz@bils.se>, December 2015.
