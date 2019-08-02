require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

helpers do
  def get_files
    Dir.glob(full_path "*").select { |file| !File.directory? file }
                        .map { |file| File.basename file }
  end
end

def users
  filepath = if ENV["RACK_ENV"] == "test"
    "./test/users.yaml"
  else
    "./users.yaml"
  end
  YAML.load(File.read(filepath))
end

def logged_in?
  session[:username]
end

def require_signed_in_user
  if !logged_in?
    set_flash_message(:error, "You are not logged in.")
    redirect "/login"
  end
end

def create_document(fname, content = "")
  File.open(full_path(fname), "w") { |file| file.write(content) }
end

def dir_path
  if ENV["RACK_ENV"] == "test"
    "./test/data"
  else
    "./data"
  end
end

def full_path(fname)
  dir_path + "/" + fname
end

def load_file_content(fname)
  content = File.read(full_path(fname))
  case File.extname(fname)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    render_markdown(content)
  end
end

def render_markdown(content)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(content)
end

def file_not_found(fname)
  set_flash_message(:error, "#{fname} not found.")
  redirect "/"
end

def set_flash_message(type, message)
  session[type] = message unless message.include?("favicon.ico")
end

def valid_title(title)
  ext = File.extname(title)
  title && title != "" && (ext == '.md' || ext == '.txt')
end

def valid_login?(user, pass)
  users[user.to_sym] == pass
end

def add_user(user, pass)
  data = users
  data[user.to_sym] = BCrypt::Password.create(pass)
  File.open("users.yaml", "w") { |file| file.write(data.to_yaml) }
end

get "/" do
  erb :home, layout: :layout
end

get "/login" do
  erb :signed_out, layout: :layout
end

get "/new" do
  require_signed_in_user
  erb :new_file, layout: :layout
end

post "/new" do
  require_signed_in_user
  fname = params[:fname]
  if valid_title(fname)
    create_document fname
    set_flash_message(:success, "#{fname} was created.")
    redirect "/"
  elsif fname == ""
    set_flash_message(:error, "A name is required.")
  else
    set_flash_message(:error, "'#{fname}' is invalid. Must be a '.md' or '.txt' file.")
  end
  status 422
  erb :new_file, layout: :layout
end

get "/signout" do
  session.delete(:username)
  set_flash_message(:success, "You have been signed out.")
  redirect "/login"
end

get "/:fname" do |fname|
  if File.file?(full_path(fname))
    load_file_content(fname)
  else
    file_not_found(fname)
  end
end

get "/:fname/edit" do |fname|
  require_signed_in_user
  @fname = fname
  if File.file?(full_path(fname))
    @content = File.read(full_path(fname))
  else
    file_not_found(fname)
  end
  erb :edit_file, layout: :layout
end

post "/:fname" do |fname|
  require_signed_in_user
  if File.file? full_path(fname)
    File.write full_path(fname), params[:content]
    set_flash_message(:success, "#{fname} updated successfully.")
  end
  redirect "/"
end

post "/:fname/delete" do |fname|
  require_signed_in_user
  if File.exist?(full_path(fname))
    File.delete(full_path(fname))
    set_flash_message(:success, "#{fname} was deleted.")
  end
  redirect "/"
end

get "/users/login" do
  erb :login, layout: :layout
end

post "/users/login" do
  user = params[:username]
  pass = params[:password]
  if valid_login?(user, pass)
    session[:username] = user
    set_flash_message(:success, "Welcome, #{user}!")
    redirect "/"
  else
    session.delete(:username) if session[:username]
    @username = user
    status 422
    set_flash_message(:error, "Invalid credentials.")
  end
  erb :login, layout: :layout
end

get "/users/register" do
  erb :register, layout: :layout
end

post "/users/register" do
  user = params[:username].strip
  pass = params[:password]
  if user == ""
    set_flash_message(:error, "User name can't be empty.")
  elsif users.keys.map(&:to_s).none? { |name| name == user }
    add_user(user, pass)
    set_flash_message(:success, "Hi, #{user}! Your account has been created.")
    redirect "/users/login"
  else
    set_flash_message(:error, "That username is already taken.")
  end
  redirect "/users/register"
end