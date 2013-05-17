
require 'mongoid'

require_relative '../../lib/application_defs'

# @todo Use this for DB recovery
Mongoid.logger = nil

require_relative 'match_slice'

module MatchConstants
  MATCH_STATE_RETRIEVAL_TIMEOUT = 10 unless const_defined? :MATCH_STATE_RETRIEVAL_TIMEOUT
end

class Match
  include Mongoid::Document
  include Mongoid::Timestamps::Updated
  include MatchConstants

  embeds_many :slices, class_name: "MatchSlice"

  scope :expired, ->(lifespan) do
    where(:updated_at.lt => (Time.new - lifespan))
  end

  def self.include_match_name
    field :match_name
    validates_presence_of :match_name
    validates_uniqueness_of :match_name
  end
  def self.include_game_definition
    field :game_definition_key, type: Symbol
    validates_presence_of :game_definition_key
    field :game_definition_file_name
  end
  def self.include_number_of_hands
    field :number_of_hands, type: Integer
    validates_presence_of :number_of_hands
    validates_numericality_of :number_of_hands, greater_than: 0, only_integer: true
  end
  def self.include_opponent_names
    field :opponent_names, type: Array
    validates_presence_of :opponent_names
  end
  def self.include_seat
    field :seat, type: Integer
    validates_presence_of :seat
    validates_numericality_of :seat, greater_than: 0, only_integer: true
  end
  def self.delete_matches_older_than(lifespan)
    expired(lifespan).delete_all
  end

  def self.delete_match!(match_id)
    begin
      match = find match_id
    rescue
    else
      match.delete
    end
  end

  def self.failsafe_while_for_match(match_id, method_for_condition)
    match = find match_id
    failsafe_while lambda{ method_for_condition.call(match) } do
      match = find match_id
    end
    match
  end

  def self.failsafe_while(method_for_condition)
    time_beginning_to_wait = Time.now
    attempts = 0
    while method_for_condition.call
      if attempts > 5
        ap "Attempts: #{attempts}"
        sleep Math.log(attempts - 4)
      end
      yield
      raise if time_limit_reached?(time_beginning_to_wait)
      attempts += 1
    end
  end
  def self.start_match(
    name,
    game_definition_key,
    opponent_names=nil,
    seat=nil,
    number_of_hands=nil,
    random_seed=nil
  )
    new(
      "match_name" => name,
      "game_definition_key" => game_definition_key,
      "opponent_names"=>opponent_names,
      'seat'=>seat,
      "number_of_hands" => number_of_hands,
      "random_seed" => random_seed
    ).finish_starting!
  end

  # Table parameters
  field :port_numbers, type: Array
  field :millisecond_response_timeout, type: Integer
  field :random_seed, type: Integer

  include_match_name
  include_game_definition
  include_number_of_hands
  include_opponent_names
  include_seat

  # Game definition information
  field :betting_type, type: String
  field :number_of_hole_cards, type: Integer

  def delete_previous_slices!(current_index)
    if current_index > 0
      slices.where(
        :_id.in => (
          slices[0..current_index-1].map do |slice|
            slice.id
          end
        )
      ).delete_all
    else
      0
    end
  end
  def finish_starting!
    local_match_name = match_name.strip
    self.match_name = local_match_name

    game_info = ApplicationDefs::GAME_DEFINITIONS[game_definition_key]

    # Adjust or initialize seat
    self.seat ||= ApplicationDefs.random_seat(game_info[:num_players])
    if seat > game_info[:num_players]
      seat = game_info[:num_players]
    end

    self.random_seed ||= ApplicationDefs.random_seed

    self.game_definition_file_name = game_info[:file]

    self.opponent_names ||= (game_info[:num_players] - 1).times.map { |i| "tester" }

    self.number_of_hands ||= 1
    self.millisecond_response_timeout ||= ApplicationDefs::DEALER_MILLISECOND_TIMEOUT

    save!

    self
  end
  def player_names(users_name='user')
    opponent_names.dup.insert seat-1, users_name
  end
  def every_bot(dealer_host)
    raise unless port_numbers.length == player_names.length ||
      opponent_ports.length == ApplicationDefs.bots(game_definition_key, opponent_names).length

    opponent_ports.zip(
      ApplicationDefs.bots(game_definition_key, opponent_names)
    ).each do |port_num, bot|
      # ENSURE THAT ALL REQUIRED KEY-VALUE PAIRS ARE INCLUDED IN THIS BOT
      # ARGUMENT HASH.
      bot_argument_hash = {
        port_number: port_num,
        millisecond_response_timeout: millisecond_response_timeout,
        server: dealer_host,
        game_def: game_definition_file_name
      }

      yield bot.run_command(bot_argument_hash).split(' ')
    end
  end
  def users_port
    port_numbers[seat - 1]
  end
  def opponent_ports
    local_port_numbers = port_numbers.dup
    users_port = local_port_numbers.delete_at(seat - 1)
    local_port_numbers
  end

  private

  def self.time_limit_reached?(start_time)
    Time.now > start_time + MATCH_STATE_RETRIEVAL_TIMEOUT
  end
end

module Stalker
  def self.start_background_job(job_name, arguments, options={ttr: MatchConstants::MATCH_STATE_RETRIEVAL_TIMEOUT})
    enqueue job_name, arguments, options
  end
end
