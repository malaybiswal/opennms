#!/usr/bin/perl

=head1 NAME

sched-outages.pl - Command-line interface to create/update scheduled-outages

=head1 SYNOPSIS

sched-outages.pl [options] [arguments ...]

=head1 EXAMPLE

sched-outages.pl --outage "Solaris Patching 08/16/2012" \
  --start "16-Aug-2012 15:00:00" --end "16-Aug-2012 17:59:59" \
  --node "yellowstone denali" --notifications --poller "example1"

=cut

use strict;
use warnings;

use DBI;
use Carp;
use Data::Dumper;
use File::Path;
use Getopt::Long;
use HTTP::Cookies;
use HTTP::Request;
use LWP::UserAgent;
use Pod::Usage;
use Socket;
use Text::Wrap;
use URI;
use URI::Escape;
use XML::Twig;

use vars qw(
        $BUILD
        $BROWSER
        $XML
        $DBH

	$url_root
	$username
	$password

	$print_help
	$print_longhelp
	$doit

	$outage_name
	$start_time
	$end_time
	@nodes
	@categories
	$send_notification
	@pollerd_packages
	@threshd_packages
	@collectd_packages

);

$BUILD = (qw$LastChangedRevision 1 $)[-1];
$XML = XML::Twig->new('pretty_print' => 'none');
$DBH = DBI->connect("dbi:Pg:dbname=opennms;host=t-opennms.gscs.rackspace.com;port=5432", 'xxx', 'xxx');

# set defaults
$url_root = 'https://host.com/opennms/rest';
$username = 'xxx';
$password = 'xxx';

$print_help  = 0;
$print_longhelp  = 0;
$doit = 1;
$outage_name = '';
$start_time  = '';
$end_time    = '';
@nodes = ();
@categories = ();
$send_notification = 0;
@pollerd_packages = ();
@threshd_packages = ();
@collectd_packages = ();

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exit.

=item B<--version>

Print the version and exit.

=item B<--username>

The username to use when connecting to the RESTful API.  This
user must have administrative privileges in the OpenNMS web UI.

Defaults to 'admin'.

=item B<--password>

The password associated with the administrative username specified
in B<-username>.

Defaults to 'admin'.

=item B<--url>

The URL of the OpenNMS REST interface.  Defaults to
'http://localhost/opennms/rest'.

=item B<--outagename>

The name of the Scheduled Outage to create or update.

=item B<--starttime>

The starting time for the outage. Must use "DD-MON-YYYY HH:MM:SS" as the format.

=item B<--endtime>

The ending time for the outage. Must use "DD-MON-YYYY HH:MM:SS" as the format.

=item B<--node>

The list of nodes to add to the outage. Can be given 
multiple times on the command line, or given as a whitespace
separated list.

=item B<--category>

Surveillence categories to use to select nodes. If the
string %h is used as part of a category name, that
category will be replaced with a list where %h has been
replaced with every node given.

=item B<--notifications>

If set, notifications are flagged for suppression.

=item B<--pollerd>

The list of pollerd packages to suppress polling for during this scheduled-outage.

=item B<--threshd>

The list of threshd packages to suppress thresholding for during this scheduled-outage.

=item B<--collectd>

The list of collectd packages to suppress collections for during this scheduled-outage.

=back

=cut

sub set_up_environment {
        $BROWSER = LWP::UserAgent->new(agent => "provision.pl/$BUILD");

        mkpath($ENV{'HOME'} . '/.opennms');
        $BROWSER->cookie_jar(
                HTTP::Cookies->new(
                        file     => $ENV{'HOME'} . '/.opennms/rest-cookies.txt',
                        autosave => 1,
                )
        );

        my $uri = URI->new($url_root);

        $BROWSER->credentials(
                $uri->host_port(),
                'OpenNMS Realm',
                $username => $password,
        );
}

sub get {
        my $path = shift;
        my $base = shift || '/sched-outages';

        my $response = $BROWSER->get( $url_root . $base . '/' . $path );
        if ($response->is_success) {
                return $response;
        }
        croak($response->status_line);
}

sub post {
        my $path      = shift;
        my $twig      = shift;
        my $base      = shift || '/sched-outages';
        my $namespace = shift || 'http://xmlns.opennms.org/xsd/config/poller/outages';

        $twig->{'att'}->{'xmlns'} = $namespace;
        my $post = HTTP::Request->new(POST => $url_root . $base . '/' . $path  );
	print "MALAY POST:",$url_root.$base.'/'.$path,"\n";
        $post->content_type('application/xml');
        $post->content($twig->sprint);
        my $response = $BROWSER->request($post);
	print "MALAY:",$response,"\n";
        if ($response->is_success) {
                return $response;
        }
        croak($response->status_line);
}

sub put {
        my $path = shift;
        my $arguments = shift;
        my $base      = shift || '/sched-outages';

        my $put = HTTP::Request->new(PUT => $url_root . $base . '/' . $path );
        $put->content_type('application/x-www-form-urlencoded');
        $put->content($arguments);
        my $response = $BROWSER->request($put);
        if ($response->is_success) {
                return $response;
        }
        croak($response->status_line);
}

sub http_delete {
        my $path = shift;
        my $base = shift || '/sched-outages';

        my $delete = HTTP::Request->new(DELETE => $url_root . $base . '/' . $path );
	my $response = $BROWSER->request($delete);
        if ($response->is_success) {
                return $response;
        }
        croak($response->status_line);
}

sub dump_xml {
        my $content = shift;

        $XML->parse($content);
        $XML->print;
        #$XML->flush;
}

sub quote_args {
    return map {"'".$_."'"} @_;
}

sub print_version {
        printf("%s build %d\n", (split('/', $0))[-1], $BUILD);
        exit 0;
}

Getopt::Long::Configure( "require_order" );
my $result = GetOptions(
        "help|h"     => \$print_help,
        "longhelp"   => \$print_longhelp,
        "version|v"  => \&print_version,
        "doit!"      => \$doit,

        "username|u=s" => \$username,
        "password|p=s" => \$password,

        "url=s"        => \$url_root,

        "outagename=s"   => \$outage_name,
        "starttime=s"    => \$start_time,
        "endtime=s"      => \$end_time,
        'node=s'         => \@nodes,
        'category=s'     => \@categories,
        'notifications!' => \$send_notification,
        'pollerd=s'      => \@pollerd_packages,
        'threshd=s'      => \@threshd_packages,
        'collectd=s'     => \@collectd_packages,
);

pod2usage(1) if $print_help;
pod2usage(-exitstatus => 0, -verbose => 2) if $print_longhelp;

set_up_environment;
if ($outage_name eq ""
    || $start_time !~ /^\d{2}-\S{3}\-\d{4} \d{2}:\d{2}:\d{2}$/
    || $end_time !~ /^\d{2}-\S{3}\-\d{4} \d{2}:\d{2}:\d{2}$/ ) {
  pod2usage(-exitstatus => 1, -verbose => 2);
}

@nodes             = split(/\s+/,join(' ',@nodes));
@pollerd_packages  = split(/\s+/,join(' ',@pollerd_packages));
@threshd_packages  = split(/\s+/,join(' ',@threshd_packages));
@collectd_packages = split(/\s+/,join(' ',@collectd_packages));

my @fqdns = ();

foreach my $svr ( @nodes ) {
  my $packed_ip = gethostbyname($svr);
  if (defined $packed_ip) {
    my $svrname = gethostbyaddr($packed_ip, AF_INET);
    if (defined $svrname && $svrname ne "") {
      push(@fqdns, $svrname);
    }
  }
}

my @var_categories = grep /\%h/, @categories;
my @real_categories = grep !/\%h/, @categories;
foreach my $category ( @var_categories ) {
  foreach my $svr ( @nodes ) {
    my $c = $category;
    $c =~ s/\%h/$svr/;
    push @real_categories, $c;
  }
}
@categories = @real_categories;
print "MALAY:",$outage_name,"\n";
my $xml = XML::Twig->new('pretty_print'=>'none');
my $root = XML::Twig::Elt->new('outage' => {'name' => $outage_name, 'type' => 'specific'});
print $root,"\n";#Added By Malay
XML::Twig::Elt->new('time' => {'begins' => $start_time, 'ends' => $end_time})
    ->paste_last_child( $root );

my($sql, $sth, $where, $pwhere);

#
# Lookup nodeid's for the nodes given on the command line.
# For example, if you give 'svrA', this will look for
# nodes named svrA or svrA.fqdn, or for
# nodes whose provisioning requisition id name is svrA.fqdn
#
$where = "";
$sql = "SELECT DISTINCT N.nodeid, N.nodelabel, N.nodeparentid FROM node N WHERE";

if (@nodes) {
  $where .= "N.nodelabel IN (".join(",", quote_args( @nodes ), quote_args( @fqdns)).") OR
  N.foreignid IN (".join(",", quote_args( @nodes ), quote_args( @fqdns)).")
";
}
if (@categories) {
  if ($where ne "") { $where .= " OR"; }
  $where .= "
  N.nodeid IN (SELECT category_node.nodeid FROM category_node, categories
               WHERE categoryname IN (".join(",", quote_args( @categories )). ")
                     AND category_node.categoryid = categories.categoryid )";
}
$where .= " OR" if $where;
$where .= " N.nodeparentid IN ( SELECT parent.nodeid FROM node parent WHERE ";
$pwhere = "";

if (@nodes) {
  $pwhere .= "
       parent.nodelabel IN (".join(",", quote_args( @nodes ), quote_args( @fqdns)).")
       OR parent.foreignid IN (".join(",", quote_args( @nodes ), quote_args( @fqdns)).")
";
}
if (@categories) {
  $pwhere .= " OR" if $pwhere;
  $pwhere .= "
       parent.nodeid
             IN (SELECT category_node.nodeid FROM category_node, categories
                 WHERE categoryname IN (".join(",", quote_args( @categories )). ")
                       AND category_node.categoryid = categories.categoryid )";
}
$where .= $pwhere;
$where .= " ) ";
$sql .= " " . $where . " ORDER BY N.nodeparentid NULLS FIRST, N.nodelabel";

print $sql, "\n";

$sth = $DBH->prepare($sql) or die $DBH->errstr;
$sth->execute() or die $sth->errstr;
while(my $h = $sth->fetchrow_hashref) {
  XML::Twig::Elt->new('node' => { id => $h->{'nodeid'} })->paste_last_child( $root );
  XML::Twig::Elt->new('#COMMENT' => "nodelabel: $h->{'nodelabel'}")->paste_last_child( $root );
}
$sth->finish;

$DBH->disconnect;

$xml->set_root($root);
$xml->print('pretty_print' => 'indented_a');

my $name = URI::Escape::uri_escape_utf8($root->{'att'}->{'name'});
post('', $root);
put($name."/notifd") if ($send_notification);
foreach my $pkg ( @pollerd_packages ) {
  put($name."/pollerd/".URI::Escape::uri_escape_utf8($pkg));
}
foreach my $pkg ( @threshd_packages ) {
  put($name."/threshd/".URI::Escape::uri_escape_utf8($pkg));
}
foreach my $pkg ( @collectd_packages ) {
  put($name."/collectd/".URI::Escape::uri_escape_utf8($pkg));
}

=back

=head1 DESCRIPTION

B<This program> provides an interface to the RESTful API of the
scheduled outages, available in OpenNMS 1.10 and higher.
of the administrative UI.

=head1 AUTHOR

Ronald Roskens <ronald.roskens@biworldwide.com>

=head1 COPYRIGHT AND DISCLAIMER

Copyright 2012, The OpenNMS Group, Inc.  All rights reserved.

OpenNMS(R) is a registered trademark of The OpenNMS Group, Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

For more information contact:

        OpenNMS Licensing <license@opennms.org>

=cut
