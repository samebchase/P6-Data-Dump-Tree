
use Data::Dump::Tree::AnsiColor ;
use Data::Dump::Tree::Enums ;
use Data::Dump::Tree::DescribeBaseObjects ;

class Data::Dump::Tree does DescribeBaseObjects 
{
has $!color = AnsiColor.new() ;

sub get_dumper(%options? is copy --> Data::Dump::Tree) is export
{
my $d = Data::Dump::Tree.new() ;

# bind standard options

for (%options<does> // ()).list -> $role { $d does $role } ; 
	
$d ;
}

sub dump($s, $title?, %options? is copy) is export
{
say get_dump($s, $title, %options) ;
}

sub get_dump($s, $title?, %options? is copy) is export
{
my $d = Data::Dump::Tree.new() ;
$d.get_dump($s, $title, %options) ;
}

method dump($s, $title?, %options? is copy)
{
say self.get_dump($s, $title, %options)
}


method get_dump($s, $title?, %options? is copy)
{
%options<color> //= True ;

my %default_colors =
	<
	title yellow   glyph reset    perl_address yellow    ddt_address blue
	link  green    key   cyan     value        reset     header      magenta 
	> ;

%options<colors> = %( |%default_colors, |(%options<colors>.kv)) ;
$!color.set_colors(%options<colors>, so %options<color>) ;

%options<address> = 0 ;
%options<display_perl_address> //= 0 ; 
%options<display_address> //= 1 ;

%options<glyphs> //= $.get_glyphs() ; #colors must be set before (for ANSI checking)

%options<width> //= 79 ;
%options<width> -= %options<glyphs><last_continuation>.chars ; # we may shift text on multiline values

%options<max_depth> //= -1 ;
%options<current_depth> = 0 ;

# ----------

self!render_element(
	(self!get_title($title, so %options<caller>), $s),
	('', '', %options<glyphs><not_last_continuation>),
	%options
	).join("\n") ~ "\n"
}

method !render($s, %options)
{
return ( %options<glyphs><empty> ~ %options<glyphs><max_depth> ~ " max depth(%options<max_depth>)")
	if %options<current_depth> + 1 == %options<max_depth> ;

temp %options<current_depth> = %options<current_depth> + 1 ;
temp %options<width> = %options<width> - %options<glyphs><last_continuation>.chars ; # text wrap

my $elements = 
	self!has_dumper_method('get_elements', $s.WHAT)
	?? $.get_elements($s) # we are $s specific 
	!! $s.can('ddt_get_elements')
		?? $s.ddt_get_elements() # $s class provided
		!! $.get_elements($s) ;  # generic handler

my @renderings ;

for $elements Z 0 .. * -> ($e, $index)
	{
	@renderings.append: self!render_element(
				$e,
				self!get_level_glyphs($index == $elements.end, %options),
				%options
				) ;
	}

@renderings
}

method !render_element($element, $glyphs, %options)
{

my ($k, $e) = $element ;

my ($glyph, $continuation_glyph, $multi_line_glyph) = $glyphs ;

my $rendered = 1 ;
my @renderings ;

my ($v, $f, $final) = self!get_vf($e) ;
$final //= DDT_NOT_FINAL ;

($v, $, $) = self.get_header($v) if $v ~~ Str ;

if ! $final && $e.^name !~~ any('Any')
	{
	(my $address, $rendered) = self!get_address(%options, $e) ;
	$f ~= $address ;
	}

if $final || $rendered 
	{
	$multi_line_glyph = %options<glyphs><last_continuation> ;
	}

my ($kvf, @ks, @vs, @fs) := self!split_entry($k, $v, $f, %options<width>) ;

if $kvf.defined
	{
	@renderings.append: $glyph ~ $kvf ;
	}
else
	{
	#@renderings.append: 'final: ' ~ $final ~ ' rendered: ' ~ $rendered ;

	@renderings.append: $glyph ~ (@ks.shift if @ks) ; 
	@renderings.append: @ks.map: { $continuation_glyph ~ $_} ; 
	@renderings.append: @vs.map: { $continuation_glyph ~ $multi_line_glyph ~ $_} ; 
	@renderings.append: @fs.map: { $continuation_glyph ~ $multi_line_glyph ~ $_} ; 
	}

if ! $final && ! $rendered
	{
	@renderings.append: self!render($e, %options).map: { $continuation_glyph ~ $_} 
	}

return @renderings ;
}

method !has_dumper_method($method_name, $type --> Bool) #TODO:is cached
{
so self.can($method_name)[0].candidates.grep: {.signature.params[1].type ~~ $type} ;
}

method !get_vf($e) 
{
self!has_dumper_method('get_header', $e.WHAT) 
	?? $.get_header($e) #specific to $e
	!! $e.can('ddt_get_header') 
		?? $e.ddt_get_header() #$e class provided
		!! $.get_header($e) ;  #generic handler
}


method !split_entry(Cool $k, Cool $v, Cool $f, Int $width)
{
my @ks = self!split_text($k, $width) ;
my @vs = self!split_text($v, $width) ; 
my @fs = self!split_text($f, $width) ;

my $kvf = @ks.join('') ~ @vs.join('') ~ @fs.join('') ;

@ks = $!color.color(@ks, 'key') ; 
@vs = $!color.color(@vs, 'value') ; 
@fs = $!color.color(@fs, 'header') ;

if +@ks > 1 || +@vs >1 || +@fs > 1
	{
	$kvf = Nil ;
	}
else
	{
	$kvf = $kvf.chars <= $width
		?? @ks.join('') ~ @vs.join('') ~ @fs.join('')
		!! Nil ;
	}

$kvf, @ks, @vs, @fs 
}

method !split_text(Cool $e, $width)
{
return ('type object') unless $e.defined ;

# given a, possibly empty, string, split the string on \n and width
($e.split("\n", :skip-empty).flatmap: {$_ ~~ m:g/(. ** {1..$width})/}).map: {$_.Str} 

#`{{{
my ($index, @lines_2) = (0) ;
for $e.lines -> $line
	{
	my $index = 0 ;

	while $index < $line.chars 
		{
		@lines_2.push: $line.substr($index, $width) ;
		$index += $width ;
		}
	}

@lines_2 ;
}}}

}

method !get_address(%options, $v)
{
state %rendered ;

my $ddt_address = %options<address>++ ;
my $perl_address = $v.WHERE ;

my ($link, $rendered) = ('', 0) ;

if defined %rendered{$perl_address}
	{
	$rendered++ ;
	$link = ' -> @' ~ %rendered{$perl_address} ;
	}
else
	{
	%rendered{$perl_address} = $ddt_address ;
	}

$perl_address = %options<display_perl_address> ?? ' ' ~ $perl_address !! '' ;

my $address = %options<display_address> 
	?? $!color.color(' @' ~ $ddt_address, 'ddt_address') 
		~ $!color.color($perl_address, 'perl_address') 
		~ $!color.color($link, 'link') 
	!! '' ;

$address, $rendered
}

method !get_level_glyphs(Bool $is_last, %options)
{
my %glyphs = %options<glyphs> ;

$!color.color(
	$is_last
		?? (%glyphs<last>, %glyphs<last_continuation>, %glyphs<not_last_continuation>)
		!! (%glyphs<not_last>, %glyphs<not_last_continuation>, %glyphs<not_last_continuation>)
	, 'glyph'
	) ;
}

method !get_class_and_parents ($a) { get_class_and_parents($a) }
sub get_class_and_parents (Any $a) is export { (($a.^name, |get_Any_parents_list($a)).map: {'.' ~ $_}).join(' ') }
 
method !get_Any_parents_list(Any $a) { get_Any_parents_list($a) }
sub get_Any_parents_list(Any $a) is export { $a.^parents.map({ $_.^name }) }

method !get_Any_attributes (Any $a)
{
my @a = try { @a = get_Any_attributes($a) }  ;
$! ?? (('DDT exception: ', "$!"),)  !! @a ;
}

multi sub get_Any_attributes (Any $a) is export 
{
$a.^attributes.grep({$_.^isa(Attribute)}).map:   #weeding out perl internal, thanks to moritz 
	{
	my $name = $_.name ;
	$name ~~ s~^(.).~$0.~ if $_.has-accessor ;

	my $value = $a.defined 
		?? $_.get_value($a) // 'Nil'
		!! 'type object' ; 

	#my $type = $_.type.^name ;

	("$name = ", $value)
	}
}

method !get_title($t, $c)
{
my Str $title = '' ;

if $t.defined
	{
	if $c.defined and $c { $title = $t ~  ' @ ' ~ callframe(3).file ~ ':' ~ callframe(3).line ~ ' ' }
	else                 { $title = $t ~ ' ' }
	}
else
	{	
	if $c.defined and $c { $title = '@ ' ~ callframe(3).file ~ ':' ~ callframe(3).line ~ ' ' }
	else                 { $title = '' }
	}

$!color.color($title, 'title') ;
}

method is_ansi { $!color.is_ansi }

multi method get_glyphs
{
self.is_ansi
	?? { last => "\x1b(0\x6d \x1b(B", not_last => "\x1b(0\x74 \x1b(B",
		last_continuation => '  ', not_last_continuation => "\x1b(0\x78 \x1b(B",
		empty => '  ', max_depth => '..',}
	!! { last => "`- ", not_last => '|- ', last_continuation => '   ', not_last_continuation => '|  ',
		empty => '   ', max_depth => '...' ,	}
}

#class
}


