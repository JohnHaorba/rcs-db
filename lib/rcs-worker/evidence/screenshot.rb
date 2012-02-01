require_relative 'single_evidence'

module RCS
module ScreenshotProcessing
  extend SingleEvidence
  
  def process
    puts "SCREENSHOT: #{@info[:data]}"
  end

  def type
    :screenshot
  end
end # ApplicationProcessing
end # DB
