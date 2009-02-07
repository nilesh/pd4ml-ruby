namespace :pdf do
  desc "Generate a PDF"
  task :generate => :environment do
    
    #pdf = PDF::PD4ML.new
    
    
    
    
  end
  
  desc "Build TTF font information"
  task :build_fonts => :environment do
    if PD4ML.build_font_information
      puts "Font information built successfully."
    else
      puts "Sorry, unable to build the font information. Please try again."
    end
  end
end
