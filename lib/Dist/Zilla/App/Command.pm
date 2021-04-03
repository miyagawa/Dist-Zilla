package Dist::Zilla::App::Command;
# ABSTRACT: base class for dzil commands

# BEGIN BOILERPLATE
use v5.20.0;
use warnings;
use utf8;
no feature 'switch';
use experimental qw(postderef postderef_qq); # This experiment gets mainlined.
# END BOILERPLATE

use App::Cmd::Setup -command;

=method zilla

This returns the Dist::Zilla object in use by the command.  If none has yet
been constructed, one will be by calling C<< Dist::Zilla->from_config >>.

(This method just delegates to the Dist::Zilla::App object!)

=cut

sub zilla {
  return $_[0]->app->zilla;
}

=method log

This method calls the C<log> method of the application's chrome.

=cut

sub log {
  $_[0]->app->chrome->logger->log($_[1]);
}

1;
