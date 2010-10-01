#!/usr/bin/perl -w

use CoGeX;
use strict;
use CGI;
use CoGe::Accessory::LogUser;

no warnings 'redefine';


my $coge = CoGeX->dbconnect();
my $FORM = new CGI;
my $dsgid = $FORM->param('dsgid');
my $dsid = $FORM->param('dsid');
my ($USER) = CoGe::Accessory::LogUser->get_user();

my $item;
my $id;
my $org;
if ($dsgid)
  {
    $item = $coge->resultset('DatasetGroup')->find($dsgid);
    next if $USER->user_name =~ /public/i && $item->organism->restricted;
    $id = $dsgid;
    $org = $item->organism->name."_dsgid";
  }
elsif ($dsid)
  {
    $item = $coge->resultset('Dataset')->find($dsid);
    next if $USER->user_name =~ /public/i && $item->organism->restricted;
    $id = $dsid;
    $org = $item->organism->name."_dsid";
  }
unless ($item)
  {
    print $FORM->header('text');
    print "Unable to complete database transaction.\n";
    print "Please contact coge administrator with a description of your problem for additional help.\n";
    exit();
  }


$org =~ s/\s+/_/g;
my $header = "Content-disposition: attachement; filename=";#test.gff\n\n";
$header .= $org;
$header .= $id;
$header .=".gff\n\n";
print $header;
$item->gff(print=>1);
