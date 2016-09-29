#!/usr/bin/env ruby
require 'json'
require 'time'
require 'open3'
require 'logger'

# Cleanup old volume
module Aws
  def self.log message
    @@logger ||= Logger.new(STDOUT)
    @@logger.debug message
  end

  module Ebs
    class Shell
      def self.run(*cmd, **opts)
        Aws.log "Run #{cmd.join("; ")}"
        stdin, stdout, stderr, wait_thr = Open3.popen3(*cmd , **opts)
        [stdout.read, stderr.read]
      end
    end

    class SnapshotCreator
      BACKUP_TAG = "auto-backup"
      attr_reader :opts

      def initialize(aws)
        @opts = {:aws => aws }
      end

      def find_tagged_volumes(age_threshold)
        volumes = get_volumes
        now = Time.now
        volumes["Volumes"].select do |volume|
          volume['Tags'] && volume["Tags"].any? { |t| t["Key"] == BACKUP_TAG }
        end
      end

      def create(age)
        Aws.log "We will create volume that has `auto-backup` tag"
        age = age.to_i
        find_tagged_volumes(age).each do |volume|
          Aws.log volume["VolumeId"]

          create_snapshot volume["VolumeId"], volume["Attachments"].first["InstanceId"]
          sleep 10 # Sleep to avoid taking all at same time
        end
      end

      private
      def get_volumes
        raw_response, err = Shell.run "#{opts[:aws]} ec2 describe-volumes"
        JSON.parse raw_response
      end

      def create_snapshot(volume_id, instance_id)
        cmd = "#{opts[:aws]} ec2 create-snapshot --volume-id #{volume_id} --description 'snapshot #{instance_id}'"
        Aws.log "Create #{cmd}"
        out, error = Shell.run cmd
        snap = JSON.parse(out)
        tag = "#{opts[:aws]} ec2 create-tags --resources #{snap['SnapshotId']} --tags Key=Name,Value=auto-backup-#{instance_id}"
        Aws.log tag
        out, error = Shell.run tag
      end

    end
  end
end

unless $PROGRAM_NAME.include? "_test"
  c = Aws::Ebs::SnapshotCreator::new(ARGV[0] || 'aws')
  c.create ARGV[1] || 45
end
