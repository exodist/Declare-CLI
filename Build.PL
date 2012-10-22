#!/usr/bin/perl
use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name => 'Declare::Opts',
    license     => 'perl',
    dist_author => 'Chad Granum <exodist7@gmail.com>',
    create_readme => 1,
    requires => {
        'Exporter::Declare' => "0.105",
    },
    build_requires => {
        'Fennec'            => '1.012',
    },
    meta_merge => {
        resources => {
            repository  => 'http://github.com/exodist/Declare-Opts',
            bugtracker  => 'http://github.com/exodist/Declare-Opts',
        },
    }
);

$build->create_build_script;
