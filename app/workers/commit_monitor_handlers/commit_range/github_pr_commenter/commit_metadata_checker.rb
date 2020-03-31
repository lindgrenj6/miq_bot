require 'rugged'

module CommitMonitorHandlers::CommitRange
  class GithubPrCommenter::CommitMetadataChecker
    include Sidekiq::Worker
    sidekiq_options :queue => :miq_bot_glacial

    include BatchEntryWorkerMixin
    include BranchWorkerMixin

    def perform(batch_entry_id, branch_id, new_commits)
      return unless find_batch_entry(batch_entry_id)
      return skip_batch_entry unless find_branch(branch_id, :pr)

      complete_batch_entry(:result => process_commits(new_commits))
    end

    private

    def process_commits(new_commits)
      @offenses = []

      new_commits.each do |commit_sha, data|
        check_for_usernames_in(commit_sha, data["message"])
      end

      @offenses
    end

    # From https://github.com/join
    #
    #     "Username may only contain alphanumeric characters or single hyphens,
    #     and cannot begin or end with a hyphen."
    #
    # For the beginning and and, we do a positive lookbehind at the beginning
    # to get the `@`, and a positive lookhead at the end to confirm their is
    # either a period or a whitespace following the "var" (instance_variable)
    #
    # Since there can't be underscores in Github usernames, this makes it so we
    # rule out partial matches of variables (@database_records having a
    # username lookup of `database`), but still catch full variable names
    # without underscores (`@foobarbaz`).
    #
    USERNAME_REGEXP = /
      (?<=^@|\s@)     # must start with a '@' (don't capture)
      [a-zA-Z0-9]     # first character must be alphanumeric
      [a-zA-Z0-9\-]*  # middle chars may be alphanumeric or hyphens
      [a-zA-Z0-9]     # last character must be alphanumeric
      (?=[\s])        # allow only variables without "_" (not captured)
    /x.freeze

    def check_for_usernames_in(commit, message)
      message.scan(USERNAME_REGEXP).each do |potential_username|
        next unless GithubService.username_lookup(potential_username)

        group   = ::Branch.github_commit_uri(fq_repo_name, commit)
        message = "Username `@#{potential_username}` detected in commit message. Consider removing."
        @offenses << OffenseMessage::Entry.new(:low, message, group)
      end
    end
  end
end
