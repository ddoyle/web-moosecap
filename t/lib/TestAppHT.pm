package TestAppHT;

use Moose;
extends 'Web::MooseCap';
with 'Web::MooseCap::Template::HT';

__PACKAGE__->meta->make_immutable; no Moose; 1;

