require "svn/repos" # load SVN Ruby bindings stuff
require "md5"
require File.join(File.dirname(__FILE__),'/repository') # load repository module

module Repository

if !defined? SVN_CONSTANTS # avoid constants already defined warnings
  SVN_CONSTANTS = {
    :author => Svn::Core::PROP_REVISION_AUTHOR, 
    :date => Svn::Core::PROP_REVISION_DATE,
    :mime_type => Svn::Core::PROP_MIME_TYPE
  }
end
if !defined? SVN_FS_TYPES
  SVN_FS_TYPES = {:fsfs => Svn::Fs::TYPE_FSFS, :bdb => Svn::Fs::TYPE_BDB}
end


class InvalidSubversionRepository < Repository::ConnectionError; end

# Implements AbstractRepository for Subversion repositories
# It implements the following paradigm:
#   1. Repositories are created by using SubversionRepository.create()
#   2. Existing repositories are opened by using either SubversionRepository.open()
#      or SubversionRepository.new()
class SubversionRepository < Repository::AbstractRepository

  # Constructor: Connects to an existing Subversion
  # repository, using Ruby bindings; Note: A repository has to be
  # created using SubversionRepository.create(), it it is not yet existent
  def initialize(connect_string)
    begin
      super(connect_string) # dummy call to super
    rescue NotImplementedError; end
    @repos_path = connect_string
    if (SubversionRepository.repository_exists?(@repos_path))
      @repos = Svn::Repos.open(@repos_path)
    else
      raise "Repository does not exist at path \"" + @repos_path + "\""
    end
  end

  # Static method: Creates a new Subversion repository at
  # location 'connect_string'
  def self.create(connect_string, fs_type = :fsfs)
    if SubversionRepository.repository_exists?(connect_string)
      raise RepositoryCollision.new("There is already a repository at #{connect_string}")
    end
    if File.exists?(connect_string)
      raise IOError.new("Could not create a repository at #{connect_string}: some directory with same name exists already")
    end
    
    # create the repository using the ruby bindings
    fs_config = {Svn::Fs::CONFIG_FS_TYPE => Repository::SVN_FS_TYPES[fs_type]} 
    Svn::Repos.create(connect_string, {}, fs_config)
    return SubversionRepository.open(connect_string)
  end
  
  # Static method: Opens an existing Subversion repository
  # at location 'connect_string'
  def self.open(connect_string)
    return SubversionRepository.new(connect_string)
  end
  
  # Static method: Reports if a Subversion repository exists
  # It's in fact a pretty hacky method checking for files typical
  # for Subversion repositories
  def self.repository_exists?(repos_path)
    repos_meta_files_exist = false
    if File.exist?(File.join(repos_path, "conf"))
      if File.exist?(File.join(repos_path, "conf/svnserve.conf"))
        if File.exist?(File.join(repos_path, "format"))
           repos_meta_files_exist = true
        end
      end
    end
    return repos_meta_files_exist
  end
  
  # Given a single object, or an array of objects of type
  # RevisionFile, try to find the file in question, and
  # return it as a string
  def stringify_files(files)
    expects_array = files.kind_of? Array
    if (!expects_array)
      files = [files]  
    end
    files.collect! {|file|   
      if (!file.kind_of? Repository::RevisionFile)
        raise TypeError.new("Expected a Repository::RevisionFile")
      end 
      begin
        @repos.fs.root(file.from_revision).file_contents(File.join(file.path, file.name)){|f| f.read}
      rescue Svn::Error::FS_NOT_FOUND => e
        raise FileDoesNotExistConflict.new(File.join(file.path, file.name))
      end
    }
    if (!expects_array)
      return files.first
    else
      return files
    end  
  end
  alias download_as_string stringify_files # create alias
  
  # Returns a Repository::SubversionRevision instance
  # holding the latest Subversion repository revision
  # number
  def get_latest_revision
    return get_revision(latest_revision_number())
  end
  
  # Returns revision_number wrapped
  # as a SubversionRevision instance
  def get_revision(revision_number)
    return Repository::SubversionRevision.new(revision_number, self)   
  end
  
  # Returns a SubversionRevision instance representing
  # a revision at a current timestamp
  #    target_timestamp
  # should be a Ruby Time instance
  def get_revision_by_timestamp(target_timestamp)
    if !target_timestamp.kind_of?(Time)
      raise "Was expecting a timestamp of type Time"
    end
    return get_revision(get_revision_number_by_timestamp(target_timestamp))
  end
  
  # Returns a Repository::TransAction object, to work with. Do operations,
  # like 'add', 'remove', etc. on the transaction instead of the repository
  def get_transaction(user_id, comment="")
    if user_id.nil?
      raise "Expected a user_id (Repository.get_transaction(user_id))"
    end
    return Repository::Transaction.new(user_id, comment)
  end
    
  # Carries out actions on a Subversion repository stored in
  # 'transaction'. In case of certain conflicts corresponding
  # Repositor::Conflict(s) are added to the transaction object
  def commit(transaction)
    jobs = transaction.jobs
    txn = @repos.fs.transaction # transaction date is set implicitly
    txn.set_prop(Repository::SVN_CONSTANTS[:author], transaction.user_id)
    jobs.each do |job|
      case job[:action]
        when :add_path
          begin
            txn = make_directory(txn, job[:path])
          rescue Repository::Conflict => e
            transaction.add_conflict(e)
          end
        when :add
          begin
            txn = add_file(txn, job[:path], job[:file_data], job[:mime_type])
          rescue Repository::Conflict => e
            transaction.add_conflict(e)
          end
        when :remove
          begin
            txn = remove_file(txn, job[:path], job[:expected_revision_number])
          rescue Repository::Conflict => e
            transaction.add_conflict(e)
          end
        when :replace
          begin
            txn = replace_file(txn, job[:path], job[:file_data], job[:mime_type], job[:expected_revision_number])
          rescue Repository::Conflict => e
            transaction.add_conflict(e)
          end
      end
    end
    
    if transaction.conflicts?
      return false
    end
    txn.commit
    return true
  end
  
  # TODO: Implement get_users(), add_user(), remove_user()
  # These are defined in Repository::AbstractRepository
  
  ####################################################################
  ##  The following stuff is semi-private. As a general rule don't use
  ##  it directly. The only reason it's public, is that
  ##  SubversionRevision needs to have access.
  ####################################################################

  # Not (!) part of the AbstractRepository API:
  # Check if given path exists in repository beeing member of
  # the provided revision
  def __path_exists?(path, revision=nil)
    return @repos.fs.root(revision).check_path(path) != 0
  end
  
  # Not (!) part of the AbstractRepository API:
  # Returns a hash of files/directories part of the requested 
  # revision; Don't use it directly, use SubversionRevision's
  # 'files_at_path' instead
  def __get_files(path="/", revision_number=nil)
    entries = @repos.fs.root(revision_number).dir_entries(path)
    entries.each do |key, value|
      entries[key] = (value.kind == 1) ? :file : :directory
    end
    return entries
  end
  
  # Not (!) part of the AbstractRepository API:
  # Returns
  #    prop
  # of Subversion repository
  def __get_property(prop, rev=nil)
    return @repos.prop(Repository::SVN_CONSTANTS[prop] || prop.to_s, rev)  
  end
  
  # Not (!) part of the AbstractRepository API:
  # This function is very similar to @repos.fs.history(); however, it's been altered a little
  # to return only an array of revision numbers. This function, in contrast to the original,
  # takes multiple paths and returns one large history for all paths given.
  def __get_history(paths, starting_revision=nil, ending_revision=nil)
    # We do the to_i's because we want to leave the value nil if it is.
    if (starting_revision.to_i < 0)
      raise "Invalid starting revision " + starting_revision.to_i.to_s + "."
    end
    revision_numbers = []
    paths = [paths].flatten
    paths.each do |path|
      hist = []
      history_function = Proc.new do |path, revision|
        yield(path, revision) if block_given?
        hist << revision
      end
      begin
        Svn::Repos.history2(@repos.fs, path, history_function, nil, starting_revision || 0, 
                       ending_revision || @repos.fs.youngest_rev, true)
      rescue Svn::Error::FS_NOT_FOUND => e
        raise Repository::FileDoesNotExistConflict.new(path)
      rescue Svn::Error::FS_NO_SUCH_REVISION => e
        raise "Ending revision " + ending_revision.to_s + " does not exist."
      end               
      revision_numbers.concat hist
    end
    return revision_numbers.sort.uniq
  end
  
  ####################################################################
  ##  Private method definitions
  ####################################################################
  
  private
  
  # Returns the most recent revision of the repository. If a path is specified, 
  # the youngest revision is returned for that path; if a revision is also specified,
  # the function will return the youngest revision that is equal to or older than the one passed.
  # 
  # This will only work for paths that have not been deleted from the repository.
  def latest_revision_number(path = nil, revision_number = nil)
     if (!path.nil?)
      begin
        data = Svn::Repos.get_committed_info(@repos.fs.root(revision_number || @repos.fs.youngest_rev), path)
        return data[0]
      rescue Svn::Error::FS_NOT_FOUND
        raise Repository::FileDoesNotExistConflict.new(path)
      rescue Svn::Error::FS_NO_SUCH_REVISION
        raise "Revision " + revision_number.to_s + " does not exist."
      end
    else
      return @repos.fs.youngest_rev
    end
  end
  
  # Assumes timestamp is a Time object (which is part of the Ruby
  # standard library)
  def get_revision_number_by_timestamp(target_timestamp)
    if !target_timestamp.kind_of?(Time)
      raise "Was expecting a timestamp of type Time"
    end
    @repos.dated_revision(target_timestamp)
  end
  
  # adds a file to a transaction and eventually to repository
  def add_file(txn, path, file_data=nil, mime_type=nil)
    if __path_exists?(path)
      raise Repository::FileExistsConflict.new(path)
    end
    txn = write_file(txn, path, file_data, mime_type)
    return txn
  end
  
  # removes a file from a transaction and eventually from repository
  def remove_file(txn, path, expected_revision_number=0)
    if latest_revision_number(path).to_i != expected_revision_number.to_i
      raise Repository::FileOutOfSyncConflict.new(path)
    end
    if !__path_exists?(path)
      raise Repository::FileDoesNotExistConflict.new(path)
    end
    txn.root.delete(path)
    return txn
  end
  
  # replaces file at provided path with file_data
  def replace_file(txn, path, file_data=nil, mime_type=nil, expected_revision_number=0)
    if latest_revision_number(path).to_i != expected_revision_number.to_i
      raise Repository::FileOutOfSyncConflict.new(path)
    end
    txn = write_file(txn, path, file_data, mime_type)
    return txn
  end
  
  def write_file(txn, path, file_data=nil, mime_type=nil)
     if (!__path_exists?(path))
      pieces = path.split("/").delete_if {|x| x == ""}
      dir_path = ""
      
      (0..pieces.length - 2).each do |index|     
        dir_path += "/" + pieces[index]
        txn = make_directory(txn, dir_path)
      end
      txn = make_file(txn, path)
    end
    stream = txn.root.apply_text(path)
    stream.write(file_data)
    stream.close
    # Set the mime type...
    txn.root.set_node_prop(path, SVN_CONSTANTS[:mime_type], mime_type)
    return txn
  end
  
  # Make a file if it's not already present.
  def make_file(txn, path)
    if (txn.root.check_path(path) == 0)
      txn.root.make_file(path)
    end
    return txn
  end
  
  # Make a directory if it's not already present.
  def make_directory(txn, path)  
    if (txn.root.check_path(path) == 0)
      txn.root.make_dir(path)
    end
    return txn
  end
end

# Convenience class, so that we can work on Revisions rather
# than repositories
class SubversionRevision < Repository::AbstractRevision

  # Constructor; Check if revision is actually present in
  # repository
  def initialize(revision_number, repo)
    @repo = repo
    begin 
      @repo.__get_property(:date, revision_number).nil? 
    rescue Svn::Error::FsNoSuchRevision
      raise RevisionDoesNotExist
    end
    super(revision_number)
  end
      
  # Return all of the files in this repository at the root directory
  def files_at_path(path)
    return files_at_path_helper(path)
  end
  
  def path_exists?(path)
    @repo.__path_exists?(path, @revision_number)
  end
  
  # Return all directories at 'path' (including subfolders?!)
  def directories_at_path(path='/')
    result = Hash.new(nil)
    raw_contents = @repo.__get_files(path, @revision_number)
    raw_contents.each do |file_name, type|
      if type == :directory
        last_modified_revision = @repo.__get_history(File.join(path, file_name)).last
        new_directory = Repository::RevisionDirectory.new(@revision_number, {
          :name => file_name,
          :path => path,
          :last_modified_revision => last_modified_revision,
          :changed => (last_modified_revision == @revision_number),
          :user_id => @repo.__get_property(:author, last_modified_revision)
        })
        result[file_name] = new_directory
      end
    end
    return result
  end
  
  # Return changed files at 'path' (recursively)
  def changed_files_at_path(path)
    return files_at_path_helper(path, true)
  end
  
  private
  
  def files_at_path_helper(path='/', only_changed=false)
    if path.nil?
      path = '/'
    end
    result = Hash.new(nil)
    raw_contents = @repo.__get_files(path, @revision_number)
    raw_contents.each do |file_name, type|
      if type == :file
        last_modified_revision = @repo.__get_history(File.join(path, file_name), nil, @revision_number).last

        if(!only_changed || (last_modified_revision == @revision_number))
          new_file = Repository::RevisionFile.new(@revision_number, {
            :name => file_name,
            :path => path,
            :last_modified_revision => last_modified_revision,
            :changed => (last_modified_revision == @revision_number),
            :user_id => @repo.__get_property(:author, last_modified_revision)
          })
          result[file_name] = new_file
        end
      end
    end
    return result
  end    


end

end
