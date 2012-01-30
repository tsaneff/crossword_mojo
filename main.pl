#!C:/perl/bin/perl.exe
use Mojolicious::Lite;
# NB: 'warning' and 'strict' are automatically enabled with 'Mojolicious::Lite'.
use Mojo::Base 'Mojolicious';
use lib 'lib';
use ValdSimple;
use Crossword;

use constant HOMEPAGE             => 'http://input.your.server.ip.n:port/';
use constant CROSSWORD_ALGORITHMS => qw( FishNet ChuckNorris TraceFull );

# Hide 'cgi-bin' directory:
sub startup {
    my $self = shift;
    $self->hook( before_dispatch => sub {
        my $self = shift;
        # notice: url must be fully-qualified or absolute, ending in '/' matters.
        $self->req->url->base(Mojo::URL->new(HOMEPAGE));
    });
}

# # # Testing # # #
get '/test' => sub {
    my $self = shift;
    $self->stash( width => 99, num_of_cells => 9801 );
    $self->render( template => 'test' );
};
# # # # # # # # # #

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
        
        # # # DEBUGGING: Display generated crossword:
        my $grid_data = '<pre>';
        my $grid = $self->crossword->{grid};
        for (my $y=0; $y < $height; ++$y){
            for (my $x=0; $x < $width; ++$x){
                $grid_data .= $grid->[$y][$x]->getData().' ';
            }
            $grid_data .= "\n";
        }
        $grid_data .= "</pre>";
        $self->render( text => $grid_data );
        # # #
        
    } else {
        $self->flash( error => "Wrong crossword width / height parameters!" ); # passing ...
        # ... value to the next http request.
        $self->redirect_to(HOMEPAGE);
    }
};

# Restrict all non wanted get requests:
get '/*' => sub {
    my $self = shift;
    $self->redirect_to(HOMEPAGE);
};

# Start mojo app as CGI script:
app->start('cgi');

# HTML Templates:
__DATA__

@@ test.html.ep
% layout 'default';
<div class="wrapper">
    %= form_for 'test2' => (method => 'post') => begin
        % my $div_flag = 0;
        % for ( my $i = 0; $i < $num_of_cells + $width; ++$i ){
        %    if ( $i % $width == 0 ){
                % if ( $i != 0){
                    &nbsp;&nbsp;</div><div class="crosword_row">
                    <%= text_field 'h_num_'.$i, class => 'header_1st_col',
                        readonly => 'readonly', value => int $i / $width # header 1st col cell
                    %>
                % } else {
                    <div class="crosword_row">
                    <%= text_field 'h_num_'.$i, class => 'header_1st_col',
                        readonly => 'readonly' # header 1st cell
                    %>
                % }
           % }
           % if ( $i < $width ){ # Setting values for header row ( value range 0 - 9 ):
                <%= text_field 'header_'.$i, class => 'header_n_col',
                    value => $i+1 # header row
                %>
           % } else {
                %= text_field $i - $width, maxlength => 1, class => 'cell'
           % }
        % }
        </div>
        <span /><div><%= submit_button 'Check!', class => 'crossword_check' %></div>
    % end
</div>

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
