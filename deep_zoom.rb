# Deep Zoom Slicer slices images into several tiles and creates xml descriptor file.
# Sliced images are compatible for use with OpenZoom, DeepZoom or Seadragon.
#
# WARNING: Will delete/overwrite existing directories, images and xml file!
#
# For further information please refer to http://openzoom.org
#
# Requirements: rmagick gem (tested with version 2.9.0)
#
# Author:: MESO Web Scapes (www.meso.net)
# License:: MPL 1.1/GPL 3/LGPL 3
#
# Contributor(s):
#   Sascha Hanssen <hanssen@meso.net>
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# Example:
#
#   require 'deep_zoom'
#   DeepZoom.new('path/to/sample.jpg').slice!
#
# Or define custom options:
#
#   file_options  = { :dir     => 'cropped',
#                     :format  => 'png',
#                     :quality => 80 }
#   slice_options = { :tile_size => 256,
#                     :overlap   => 4 }
#
#   img_path = 'path/to/sample.jpg'
#
#   DeepZoom.new(img_path, file_options).slice!(slice_options)
#
# Remove Deep Zoom created files:
#
#   DeepZoom.new(img_path, file_options).remove_files!



class DeepZoom
  require 'rubygems'
  require "RMagick"
  include Magick


  # Loads the given image, initializes attributes and directory and file path variables,
  # removes existing xml descriptor file and target directories.
  #
  # Options: dir: absolute directory to store slices in
  #          format: image format of resulting tiles. set to nil to use original extension
  def initialize(image_path, options = {})
    options = { :dir     => nil,
                :format  => 'jpg',
                :quality => 75  }.merge options

    @image_path = image_path

    return unless File.file? @image_path

    # set overall variables
    orig_filename, orig_extension = split_to_filename_and_extension(File.basename(@image_path))
    @extension = options[:format] ? options[:format] : orig_extension
    @quality = options[:quality]

    # set pathes to files and directories
    root_dir = options[:dir] ? options[:dir] : File.dirname(@image_path)
    @levels_root_dir     = File.join(root_dir, orig_filename + '_files')
    @xml_descriptor_path = File.join(root_dir, orig_filename + '.xml')
  end

  
  # Slices image into several tiles.
  #
  # WARNING: Will delete/overwrite existing directories, images and xml files!
  #
  # Options: tile_size: width and height of resulting tiles
  #          overlap: overlapping of each square in top and left direction (0-10)
  def slice!(options = {})
    options = { :tile_size => 254,
                :overlap   => 1 }.merge options
    
    # load image
    image = Magick::Image::read(@image_path).first
    image.strip! # remove meta information

    orig_width, orig_height = image.columns, image.rows

    remove_files!

    # iterate over all levels (= zoom stages)
    max_level(orig_width, orig_height).downto(0) do |level|
      width, height = image.columns, image.rows
      puts "level #{level} is #{width} x #{height}"
      
      current_level_dir = File.join(@levels_root_dir, level.to_s)
      FileUtils.mkdir_p(current_level_dir)
      
      # iterate over columns
      x, col_count = 0, 0
      while x < width      
        # iterate over rows
        y, row_count = 0, 0
        while y < height          
          dest_path = File.join(current_level_dir, "#{col_count}_#{row_count}.#{@extension}")
          tile_width, tile_height = tile_dimensions(x, y, options[:tile_size], options[:overlap])
          
          save_cropped_image(image, dest_path, x, y, tile_width, tile_height, @quality)
          
          y += (tile_height - (2 * options[:overlap]))
          row_count += 1
        end
        x += (tile_width - (2 * options[:overlap]))
        col_count += 1
      end
      
      image.resize!(0.5)
    end

    # generate xml descriptor and write file
    write_xml_descriptor(@xml_descriptor_path,
                         :tile_size => options[:tile_size],
                         :overlap   => options[:overlap],
                         :format    => @extension,
                         :width     => orig_width,
                         :height    => orig_height)
  end

  
  # Removes files and directories which would be created by slice! process.
  # Ensures clean structures after build process or can be used to do a cleanup.
  def remove_files!
    files_existed = (File.file?(@xml_descriptor_path) or File.directory?(@levels_root_dir))

    File.delete @xml_descriptor_path if File.file? @xml_descriptor_path
    FileUtils.remove_dir @levels_root_dir if File.directory? @levels_root_dir

    return files_existed
  end



protected



  # Determines width and height for tiles, dependent of tile position.
  # Center tiles have overlapping on each side.
  # Borders have no overlapping on the border side and overlapping on all other sides.
  # Corners have only overlapping on the right and lower border.
  def tile_dimensions(x, y, tile_size, overlap)
    overlapping_tile_size = tile_size + (2 * overlap)
    border_tile_size      = tile_size + overlap
    
    tile_width  = (x > 0) ? overlapping_tile_size : border_tile_size
    tile_height = (y > 0) ? overlapping_tile_size : border_tile_size
    
    return tile_width, tile_height
  end


  # Calculates how often an image with given dimension can 
  # be divided by two until 1x1 px are reached.
  def max_level(width, height)
    return (Math.log([width, height].max) / Math.log(2)).ceil
  end

  
  # Crops part of src image and writes it to dest path.
  #
  # Params: src: may be an Magick::Image object or a path to an image.
  #         dest: path where cropped image should be stored.
  #         x, y: offset from upper left corner of source image.
  #         width, height: width and height of cropped image.
  #         quality: compression level 0-100 (or 0.0-1.0), lower number means higher compression.
  def save_cropped_image(src, dest, x, y, width, height, quality = 75)
    if src.is_a? Magick::Image
      img = src
    else
      img = Magick::Image::read(src).first
    end
    
    quality = quality * 100 if quality < 1

    # The crop method retains the offset information in the cropped image.
    # To reset the offset data, adding true as the last argument to crop.
    cropped = img.crop(x, y, width, height, true)
    cropped.write(dest) { self.quality = quality }
  end
  
  
  # Writes Deep Zoom XML Descriptor file
  def write_xml_descriptor(path, attr)
    attr = { :xmlns => 'http://schemas.microsoft.com/deepzoom/2008' }.merge attr
    
    xml = "<?xml version='1.0' encoding='UTF-8'?>" + 
          "<Image TileSize='#{attr[:tile_size]}' Overlap='#{attr[:overlap]}' " + 
            "Format='#{attr[:format]}' xmlns='#{attr[:xmlns]}'>" + 
          "<Size Width='#{attr[:width]}' Height='#{attr[:height]}'/>" + 
          "</Image>"

    open(path, "w") { |file| file.puts(xml) }
  end

  
  # Returns filename (without path and extension) and its extension as array.
  # path/to/file.txt -> ['file', 'txt']
  def split_to_filename_and_extension(path)
    extension = File.extname(path).gsub('.', '')
    filename  = File.basename(path, '.' + extension) 
    return filename, extension
  end  
end
