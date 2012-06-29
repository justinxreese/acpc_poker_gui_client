
# require each bot runner class
Dir.glob("#{File.expand_path('../../', __FILE__)}/lib/bots/run_*_bot.rb").each do |runner_class|
  begin
    require runner_class
  rescue 
  end
end

# Assortment of constant definitions.
module ApplicationDefs

  # @return [String] Improper amount warning message.
  IMPROPER_AMOUNT_MESSAGE = "Improper amount entered" unless const_defined?(:IMPROPER_AMOUNT_MESSAGE)

  GAME_DEFINITIONS = {
    two_player_nolimit: {
      file: File.expand_path('../../vendor/project_acpc_server/holdem.nolimit.2p.reverse_blinds.game', __FILE__),
      text: '2-player no-limit',
      bots: {
        # 'UAlberta2012' => RunUAlberta2012Bot, # @todo Disable these only if constant is not available
        # 'UAlberta2011' => RunUAlberta2011Bot,
        'tester' => RunTestingBot
      }
    },
    two_player_limit: {
      file: File.expand_path('../../vendor/project_acpc_server/holdem.limit.2p.reverse_blinds.game', __FILE__),
      text: '2-player limit',
      bots: {'tester' => RunTestingBot}
    }
  }
end
