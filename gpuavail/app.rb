require 'erubi'
require './command'

set :erb, :escape_html => true

if development?
  require 'sinatra/reloader'
  also_reload './command.rb'
end

helpers do
  def dashboard_title
    "ACES OnDemand Portal"
  end

  def dashboard_url
    "/pun/sys/dashboard/"
  end

  def title
    "ACES GPU Availability"
  end
end

# Define a route at the root '/' of the app.
get '/' do
  @command = Command.new
  @output, @error = @command.exec

  # Render the view
  erb :index
end
