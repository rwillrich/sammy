# jsdoc.rb (by quirkey/Aaron Quint)
#
# Simple Documentation generator for JavaScript Class files.
#
# usage :
# ruby jsdoc.rb FILE
#
# looks for files formatted like
#
# MyClass = Class.extend({
#   ...
#   // My method does this
#   // with multi line comments
#   myMethod: function(arg1, arg2) {
#     ...
#   },
#
#   _noDoc: function() {
#     ...
#   }
#
# });

require 'rubygems'
require 'haml'
require 'rdiscount'
require 'active_support/ordered_hash'
require 'yajl'

class JSDoc

  KLASS_REGEXP     = /^\s*([A-Z][\w\d\.]+)\s+=\s+function\s*\(([^\)]+)?\)/
  FUNCTION_REGEXP  = /(\/\/(.*)|(([\w\d_\$]+)\:\s*function\s*\(([\w\d\s,]+)?\))|(function\s+([\w\d_\$]+)\(([\w\d\s,]+)?\)))/im
  ATTRIBUTE_REGEXP = /^\s+([\w\d_\$]+)\:\s+(.*)\,\s+/i

  def initialize(*paths)
    @paths = []
    paths.flatten.each do |path|
      path = File.expand_path(path)
      if File.directory?(path)
        Dir[path + '/*.js'].each do |p|
          @paths << p
        end
      else
        @paths << path
      end
    end
    @docs = {}
  end

  def parse!
    @paths.each do |path|
      @docs.merge!(parse_file(path))
    end
    sort_docs
  end

  def parse_file(filename)
    puts "parsing #{filename}"
    file = File.open(filename)

    klass   = {:klass => 'Top Level'}
    context = nil
    current = nil
    comment = ""
    docs    = ActiveSupport::OrderedHash.new({})
    file.each do |line|
      if klass_match = line.match(KLASS_REGEXP)
        klass = {
          :klass => klass_match[1].to_s.strip,
          :args => klass_match[2].to_s.split(',').collect {|a| a.strip },
          :doc => "",
          :filename => filename,
          :lineno => file.lineno
        }
        if context == :comment
          klass[:doc] = comment
          comment = ""
        end
        docs[klass] = {:methods => [], :attributes => []}
      else
        if line_match = line.match(FUNCTION_REGEXP)
          current = ((line_match[0] =~ /^\/\//) ? :comment : :method)
          if current == :comment
            this_comment = line_match[2].to_s
            if context == :comment
              comment << this_comment
            else
              comment = this_comment
            end
          elsif current == :method
            name = line_match[4].to_s
            args = line_match[5].to_s.split(',').collect {|a| a.strip }
            if !(name.nil? || name.strip == '')
              meth = {
                :klass => klass,
                :name => name,
                :args => args,
                :filename => filename,
                :lineno => file.lineno
              }
              if context == :comment
                if !(comment.nil? || comment.strip == '')
                  meth[:doc] = comment
                  comment = ""
                  docs[klass][:methods] << meth if docs[klass] && docs[klass][:methods]
                end
              end
            end
          end
        elsif line_match = line.match(ATTRIBUTE_REGEXP)
          current = :attribute
          attribute = {
            :klass => klass,
            :name  => line_match[1].to_s,
            :default => line_match[2].to_s,
            :filename => filename,
            :lineno   => file.lineno
          }
          if context == :comment
            if !(comment.nil? || comment.strip == '')
              attribute[:doc] = comment
              comment = ""
              docs[klass][:attributes] << attribute if docs[klass] && docs[klass][:attributes]
            end
          end
        else
          current = nil
        end
        context = current
      end
    end
    file.close
    puts docs.inspect
    docs
  end

  def sort_docs
    # sort the methods and attributes for each klass
    @docs.each do |klass, klass_methods|
      @docs[klass][:attributes] = klass_methods[:attributes].sort {|a,b| a[:name] <=> b[:name] }
      @docs[klass][:methods] = klass_methods[:methods].sort {|a,b| a[:name] <=> b[:name] }
    end

    @docs = @docs.reject do |klass, klass_methods|
      # get rid of undocumented classes
      klass[:doc].nil? || klass[:doc].to_s.strip == ''
    end.sort {|a, b|
      a[0][:klass] <=> b[0][:klass]
    }
  end

  def to_json
    Yajl::Encoder.encode(@docs, :pretty => true)
  end
end


# class RDoc::Markup::ToHtml
#
#   def accept_verbatim(am, fragment)
#     @res << annotate("{% highlight javascript %}") << "\n"
#     @res << fragment.txt.split(/\n/).collect {|l| l.gsub(/^\s{4}/,'') }.join("\n")
#     @res << "\n" << annotate("{% endhighlight %}") << "\n"
#   end
#
# end

module Helper
  extend self

  def convert(text)
    final_text = ""
    text.each_line do |l|
      final_text << l.gsub(/^\ #/,'#')
    end
    final_text = RDiscount.new(final_text).to_html
    final_text.gsub!('<pre><code>', "{% highlight javascript %}\n")
    final_text.gsub!('</code></pre>', "{% endhighlight %}\n")
    final_text
  end

end

# rdoc = RDoc::Markup::ToHtml.new
# template = File.read(File.join(File.dirname(__FILE__), 'doc.haml'))
# puts Haml::Engine.new(template).to_html(Helper, {:doc => docs})

if __FILE__ == $0
  puts "Running JSDOC on #{ARGV}"
  jsdoc = JSDoc.new(*ARGV)
  jsdoc.parse!
  puts jsdoc.to_json
end
