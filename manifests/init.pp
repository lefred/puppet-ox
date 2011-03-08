# Class: ox
#
# This module manages ox
#
# Parameters:
#
# Actions:
#
# Requires:
#
# Sample Usage:
#
# [Remember: No empty lines between comments and class definition]
class ox {

    include postfix 
    include ldap::server 
    include mysql::server 
    include cyrus::imap 
    include cyrus::sasl 
    include apache::server 
    
    $ox_admin_master_user="oxadminmaster"
    $ox_admin_master_passwd="secret"
    $ox_context_admin_user="mailadmin"
    $ox_context_admin_passwd="secret"
    $ox_mysql_user="openxchange"
    $ox_mysql_passwd="secret"

    yumrepo {
        "open-xchange":
            descr => "OpenXchange Repo",
            baseurl => "http://software.open-xchange.com/OX6/6.18/RHEL5/",
            enabled => 1,
            gpgcheck => 0,
    }
    
    yumrepo {
        "open-xchange-unsupported":
            descr => "OpenXchange Repo Unsupported",
            baseurl => "http://software.open-xchange.com/OX6/unsupported/repo/RHEL5/",
            enabled => 1,
            gpgcheck => 0,
    }
    
    host {
        "ox1":
            ensure => "present",
            host_aliases =>  "",
            ip => "";
    }

    host {
        "ox2":
            ensure => "present",
            host_aliases => "",
            ip => "";
    }

    package {
        "open-xchange-spamhandler-spamassassin":
            ensure => installed,
            require => Yumrepo["open-xchange"],
    }
    
    package {
        "open-xchange":
            ensure => installed,
            require => [ Package["open-xchange-spamhandler-spamassassin"], Package["open-xchange-authentication-ldap"] ],
    }
    
    package {
        "open-xchange-meta-server":
            ensure => installed,
            require => Package["open-xchange"],
    }
    
    exec {
        "ox_init_db":
            command => "/opt/open-xchange/sbin/initconfigdb --configdb-pass=db_password -a",
            subscribe => Package["open-xchange-meta-server"],
            refreshonly => true,
    }
    
    exec {
        "ox_conf":
            command => "/opt/open-xchange/sbin/oxinstaller --no-license --servername=$hostname --configdb-pass=$ox_mysql_passwd --master-pass=$ox_admin_master_passwd --ajp-bind-port=localhost",
            subscribe => Package["open-xchange-meta-server"],
            refreshonly => true,
    }
     
    package {
        "open-xchange-calendar-printing":
            ensure => installed,
            require => Package["open-xchange"],
    }
    
    package {
        "open-xchange-meta-admin":
            ensure => installed,
            require => Package["open-xchange"],
    }
    
    package {
        "open-xchange-meta-pubsub":
            ensure => installed,
            require => Package["open-xchange"],
    }
    
    package {
        "open-xchange-meta-gui":
            ensure => installed,
            require => Package["open-xchange"],
    }
    
    package {
        "oxldapsync":
            ensure => installed,
            require => Yumrepo["open-xchange-unsupported"],
    }
    
    package {
        "open-xchange-authentication-ldap":
            ensure => installed,
            require => Yumrepo["open-xchange"],
    }
    
    file {
        "/etc/httpd/conf.d/proxy_ajp.conf":
            ensure  => present,
            mode    => 0444,
            owner   => "root",
            group   => "root",
            source  => "puppet:///modules/ox/proxy_ajp.conf",
            require => Package["open-xchange-meta-server"];
    }
    
    file {
        "/etc/httpd/conf.d/ox.conf":
            ensure  => present,
            mode    => 0444,
            owner   => "root",
            group   => "root",
            source  => "puppet:///modules/ox/ox.conf",
            require => Package["open-xchange-meta-server"];
    }
   
    file {
       "/opt/open-xchange/etc/groupware/ldapauth.properties":
            ensure  => present,
            mode    => 0444,
            owner   => "root",
            group   => "root",
            source  => "puppet:///modules/ox/ldapauth.properties",
            require => Package["open-xchange-authentication-ldap"]; 
    } 

    file {
       "/opt/oxldapsync/etc/ldapsync.conf":
            ensure  => present,
            mode    => 0444,
            owner   => "root",
            group   => "root",
            source  => "puppet:///modules/ox/ldapsync.conf",
            require => Package["oxldapsync"]; 
    } 
    
    file {
        "/opt/oxldapsync/etc/mapping.openldap.conf":
            ensure  => present,
            mode    => 0444,
            owner   => "root",
            group   => "root",
            source  => "puppet:///modules/ox/mapping.openldap.conf",
            require => Package["oxldapsync"];
    }

    file {
        "/var/opt/filestore/":
            ensure => present,
            mode   => 0755,
            owner  => "open-xchange",
            group  => "open-xchange",
            require => Package["open-xchange-meta-server"],
    }
  
    exec { "setupox":
        unless => "/opt/open-xchange/sbin/listcontext  -A $ox_admin_master_user -P $ox_admin_master_passwd | grep defaultcontext || echo ox not running",
        command =>"/opt/open-xchange/sbin/initconfigdb --configdb-pass=$ox_mysql_passwd;
                   /opt/open-xchange/sbin/oxinstaller --no-license --servername=oxserver --configdb-pass=$ox_mysql_passwd --master-pass=$ox_admin_master_passwd --ajp-bind-port=localhost;
                   /opt/open-xchange/sbin/registerserver -n oxserver -A $ox_admin_master_user -P $ox_admin_master_passwd;
                   /opt/open-xchange/sbin/registerfilestore -A $ox_admin_master_user -P $ox_admin_master_passwd -t file:/var/opt/filestore;
                   /opt/open-xchange/sbin/registerdatabase -A $ox_admin_master_user -P $ox_admin_master_passwd -n oxdatabase -p $ox_mysql_passwd -m true;
                   /opt/open-xchange/sbin/createcontext -A $ox_admin_master_user -P $ox_admin_master_passwd -c 1 -u $ox_context_admin_user -d 'Context Admin' -g Admin -s User -p $ox_context_admin_passwd -L defaultcontext -q 1024 --access-combination-name=all;
                   ",
        require => File["/var/opt/filestore"]

    }

    define grant( $user, $password, $db, $host, $permission ) {
    
        exec { "add-${name}":
            unless => "/usr/bin/mysql -u${user} -p${password}",
            command => "/usr/bin/mysql -uroot -e \"grant ${permission} on ${db}.* to ${user}@'$host' identified by '$password';\"",
            require => Service["mysqld"],
        }
    }
    
    grant { 
        "oxreplica":
            user => "replica",
            password => "repl123",
            host => "%",
            db => "*",
            permission => "replication slave, super, replication client",
    }
    
    grant { 
        "oxuser":
            user => $ox_mysql_user,
            password => $ox_mysql_passwd,
            db => "*",
            host => "localhost",
            permission => "all",
    }

}
