#!C:/perl/bin/perl.exe
use Mojolicious::Lite;
# NB: 'warning' and 'strict' are automatically enabled with 'Mojolicious::Lite'.
use Mojo::Base 'Mojolicious';
use lib 'lib';
use ValdSimple;
use Crossword;
use Guess2Web;

use constant HOMEPAGE             => 'http://input.your.server.ip.n:port/';
use constant CROSSWORD_ALGORITHMS => qw( FishNet ChuckNorris TraceFull );
use constant WRONG_CELL_BKGCOLOR  => '#FF0000'; # red

# Hide 'cgi-bin' directory:
sub startup {
    my $self = shift;
    $self->hook( before_dispatch => sub {
        my $self = shift;
        # notice: url must be fully-qualified or absolute, ending in '/' matters.
        $self->req->url->base(Mojo::URL->new(HOMEPAGE));
    });
}

# Render the 'index' page:
get '/' => sub {
    my $self = shift;
    
    $self->stash( home => HOMEPAGE, algorithms => [CROSSWORD_ALGORITHMS] ); # passing value to the template.
    $self->render( template => 'index' );
};

# Crossword generation page:
post '/crossword_gen' => sub {
    my $self = shift;
    
    my $height = $self->req->param('crossword_h');
    my $width  = $self->req->param('crossword_w');
    my $alg    = $self->req->param('algorithm');
    
    my $validator = ValdSimple->new(
        [ sub{ shift =~ /^[2-9]$|^[1-9][0-9]$/ } ] # Passed num. range is: 2-99.
    );
    
    if ( $validator->validate( [$height, $width]) ){
        my $crossword = Crossword->new({ height =>  $height, width => $width });
        
        helper crossword => sub { return $crossword };
        $self->crossword->fill( { algorithm => $alg } );
        
        my $g2w = Guess2Web->new();
        my $cw_control  = $self->crossword->getGrid->getAsFlatArrayRef;
        my ( $cw_colormap, $guessl_pane ) = $g2w->conv_guess2colorseq(
            $cw_control, $self->crossword->getGrid->getGuesses
        );
        
        $self->session(
            home         => HOMEPAGE,
            width        => $width,
            num_of_cells => $height * $width,
            guessl_pane  => $guessl_pane,
            cw_colormap  => $cw_colormap,
            cw_control   => $cw_control
        );
        $self->redirect_to(HOMEPAGE.'ui_handler');
    } else {
        $self->flash( error => "Wrong crossword width / height parameters!" ); # passing ...
        # ... value to the next http request.
        $self->redirect_to(HOMEPAGE);
    }
};

get '/ui_handler' => sub {
    my $self = shift;
    
    if ( $self->session('cw_control') ){ # Check if session variable exists!
        my $cw_filled = [ ('') x $self->session->{num_of_cells} ];
        
        $self->flash( cw_filled => $cw_filled );
        $self->redirect_to(HOMEPAGE.'crossword_ui');   
    } else {
        $self->redirect_to(HOMEPAGE);
    }
};

post '/ui_handler' => sub {
    my $self = shift;
    
    my $cw_filled;
    $cw_filled = [ map { lc $_ } $self->req->param('filled_array') ];
    
    # Check correctness of user input
    my $completed = 1;
    for ( my $i = 0; $i < $self->session->{num_of_cells}; ++$i ){
        if ( $cw_filled->[$i] eq $self->session->{cw_control}->[$i]){
            if ( $self->session->{cw_colormap}->[$i] eq WRONG_CELL_BKGCOLOR ){
                $self->session->{cw_colormap}->[$i] = '#000000';
            }
            next;
        }
        $completed = 0;
        next if $cw_filled->[$i] eq '';
        $self->session->{cw_colormap}->[$i] = WRONG_CELL_BKGCOLOR;
    }
    
    if ( $completed ){
        delete $self->session->{$_} foreach (
            'home',
            'width',
            'num_of_cells',
            'guessl_pane',
            'cw_colormap',
            'cw_control'
        );
        $self->session( completed => 1 );
        $self->redirect_to(HOMEPAGE.'congrats');
    } else {
        $self->flash( cw_filled => $cw_filled );
        $self->redirect_to(HOMEPAGE.'crossword_ui');
    }
};

get '/crossword_ui' => sub {
    my $self = shift;
    
    if ( $self->flash( 'cw_filled' ) ){ # Check if flash value exists!
        $self->render( template => 'crossword_ui' );
    } else {
        $self->redirect_to(HOMEPAGE);
    }
};

get '/congrats' => sub {
    my $self = shift;
    
    if ( $self->session('completed') ){ # Check if session variable exists!
        delete $self->session->{completed};
        $self->render( template => 'congrats' );
    } else {
        $self->redirect_to(HOMEPAGE.'crossword_ui');
    }
};

# Restrict all non wanted get requests:
get '/*' => sub {
    my $self = shift;
    $self->redirect_to(HOMEPAGE);
};

# Session identifier:
app->sessions->default_expiration( 5 * 60 );
app->secret('zcroswordZzzzZzZzzzzZzzz');

# Start mojo app as CGI script:
app->start('cgi');

# HTML Templates:
__DATA__


@@ crossword_ui.html.ep
% layout 'default';

% my $home         = session 'home';
% my $width        = session 'width';
% my $num_of_cells = session 'num_of_cells';
% my $guessl_pane  = session 'guessl_pane';
% my $cw_colormap  = session 'cw_colormap';
% my $cw_control   = session 'cw_control';
% my $cw_filled    = flash   'cw_filled';

<div class="wrapper">
    %= form_for $home.'ui_handler' => (method => 'post') => begin
        % for ( my $i = 0; $i < $num_of_cells + $width; ++$i ){
           % if ( $i % $width == 0 ){
                % if ( $i != 0){
                    &nbsp;&nbsp;</div><div class="crosword_row">
                    <%= text_field 'header', class => 'header_1st_col',
                            disabled => 'disabled', value => int $i / $width # header 1st col cell
                    %>
                % } else {
                    <div class="crosword_row">
                    <%= text_field 'header', class => 'header_1st_col',
                            disabled => 'disabled' # header 1st cell
                    %>
                % }
           % }
           % if ( $i < $width ){ # Setting values for header row ( value range 0 - 9 ):
                <%= text_field 'header', class => 'header_n_col',
                        disabled => 'disabled', value => $i+1 # header row
                %>
           % } else {
                % if ( $cw_control->[$i-$width] =~ /^\d+$/ ){ # <- Guess
                    <%= text_field 'filled_array', class => 'cell', readonly => 'readonly',
                        style => 'background-color:'.$cw_colormap->[$i-$width],
                        value => $cw_control->[$i-$width]
                    %>
                % } elsif ( $cw_control->[$i-$width] eq '%' ){ # <- Grave
                    <%= text_field 'filled_array', class => 'cell', readonly => 'readonly',
                        style => 'background-color:#000000',
                        value => $cw_control->[$i-$width]
                    %>
                % } else { # <- Letter
                    <%= text_field 'filled_array', maxlength => 1, class => 'cell',
                        value => $cw_filled->[$i-$width],
                        style => 'color:'.(($cw_colormap->[$i-$width] eq '' ) ?
                            '#000000' : $cw_colormap->[$i-$width]);
                    %>
                % }
           % }
        % }
        </div>
        <span /><div><%= submit_button 'Check!', class => 'crossword_check' %></div>
    % end
</div>
<table class="guesslist_pane">
    <tr><th class="guesslist_pane">N</th class="guesslist_pane"><th class="guesslist_pane">Arrow</th><th class="guesslist_pane">Description</th></tr>
    % foreach my $guess ( @{$guessl_pane} ){
        % foreach my $arrow (sort {$a cmp $b} keys %{$guess->{arrows}}){
            <tr>
               <td class="guesslist_pane" style="background-color:<%= $guess->{color} %>;" ><%= $guess->{seq} %></td>
               <td class="guesslist_pane"><img src="public/<%= $arrow %>.png" /></td>
               <td class="guesslist_pane"><%= $guess->{arrows}->{$arrow} %></td>
            </tr>
        % }
    % }
</table>

@@ index.html.ep
% layout 'default';

<h2><%= flash 'error' %></h2>

<h2>Input size and algorithm for your crossword.</h2>

%= form_for $home.'crossword_gen' => (method => 'post') => begin
    <div><%= select_field algorithm => $algorithms %></div><br />
    <div>Height: <%= text_field 'crossword_h', size => 2, maxlength => 2 %></div><br />
    <div>Width:  <%= text_field 'crossword_w', size => 2, maxlength => 2 %></div><br />
    <%= submit_button 'Generate!' %>
% end


@@ congrats.html.ep
% layout 'default';
<img src="public/congrats.gif" /><br />
%= link_to 'Solve another crossword?' => 'index'


@@ layouts/default.html.ep
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <title>Crossword Mojo v0.0.1</title>
    <link rel="stylesheet" type="text/css" href="public/content.css" />
  </head>
  <body>
    <%= content %>
  </body>
</html>
