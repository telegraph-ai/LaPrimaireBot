# encoding: utf-8

=begin
    Bot LaPrimaire.org helps french citizens participate to LaPrimaire.org
    Copyright (C) 2016 Telegraph.ai

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

module Bot
	class Users
		def self.load_queries
			queries={
			'register_user'=><<END,
INSERT INTO citizens (user_id,firstname,lastname,username,session,settings) VALUES ($1,$2,$3,$4,$5::jsonb,$6::jsonb) RETURNING *
END
			'get_user_by_email'=><<END,
SELECT z.*,c.slug,c.zipcode,c.departement,c.lat_deg,c.lon_deg FROM citizens AS z LEFT JOIN cities AS c ON (c.city_id=z.city_id) WHERE z.email=$1
END
			'get_user_by_user_id'=><<END,
SELECT z.*,c.slug,c.zipcode,c.departement,c.lat_deg,c.lon_deg FROM citizens AS z LEFT JOIN cities AS c ON (c.city_id=z.city_id) WHERE z.user_id=$1
END
			'set_city'=><<END,
UPDATE citizens SET city=$1, city_id=v.city_id FROM (SELECT (SELECT b.city_id FROM cities AS b WHERE upper(b.name)=$1) as city_id) AS v WHERE citizens.user_id=$2;
END
			'set_city_using_zipcode'=><<END,
UPDATE citizens SET city=$1, city_id=v.city_id FROM (SELECT (SELECT b.city_id FROM cities AS b WHERE upper(b.name)=$1 AND b.zipcode=$3) as city_id) AS v WHERE citizens.user_id=$2;
END
			'set_session'=><<END,
UPDATE citizens SET session=$1::jsonb WHERE user_id=$2;
END
			'set_settings'=><<END,
UPDATE citizens SET settings=$1::jsonb WHERE user_id=$2;
END
			'set_email'=><<END,
UPDATE citizens SET email=$1 WHERE user_id=$2;
END
			'set_country'=><<END,
UPDATE citizens SET country=$1 WHERE user_id=$2;
END
			'set_zipcode'=><<END,
UPDATE citizens SET city_id=v.city_id FROM cities AS v WHERE v.zipcode=$1 AND citizens.user_id=$2;
END
			'remove_user'=><<END,
DELETE FROM citizens WHERE user_id=$1
END
			'add_to_waiting_list'=><<END,
INSERT INTO waiting_list (user_id,firstname,lastname) VALUES ($1,$2,$3) RETURNING *
END
			'remove_from_waiting_list'=><<END,
DELETE FROM waiting_list WHERE user_id=$1
END
			'delete_beta_code'=><<END,
DELETE FROM beta_codes WHERE code=$1 RETURNING code
END
			'get_user_position_in_wait_list'=><<END,
SELECT a.position, b.total FROM (SELECT COUNT(w.user_id) AS position FROM waiting_list AS w, (SELECT user_id,registered FROM waiting_list WHERE user_id=$1) AS z WHERE w.registered<=z.registered) AS a, (SELECT count(*) AS total FROM waiting_list) AS b;
END
			}
			queries.each { |k,v| Bot::Db.prepare(k,v) }
		end

		def initialize()
			@users={}
		end

		def add(user)
			bot_session={
				'last_update_id'=>nil,
				'current'=>nil,
				'expected_input'=>"answer",
				'expected_input_size'=>-1,
				'buffer'=>""
			}
			user_settings={
				'blocked'=>{
					'abuse'=>false, # the user has clearly done bad things 
					'not_allowed'=>false, # the information provided by the user do not allow him to participate
					'review'=>false, # the user has done too many bad reviews and cannot review anymore
					'add_candidate'=>false # the user has proposed too many rejected candidates and cannot propose candidates anymore
				},
				'limits'=>{
					'candidate_proposals'=>MAX_CANDIDATES_PROPOSAL,
					'candidate_reviews'=>nil
				},
				'actions'=>{
					'first_help_given'=>false,
					'nb_candidates_proposed'=>0,
					'nb_candidates_reviewed'=>0,
					'beta_nb_position_checked'=>0,
				},
				'roles'=>{
					'betatester'=>false,
					'reviewer'=>false,
				},
				'legal'=>{
					'charte'=>false,
					'can_vote'=>false,
					'email_optin'=>false
				}
			}
			return Bot::Db.query("register_user",[user.id,user.first_name,user.last_name,user.username,JSON.dump(bot_session),JSON.dump(user_settings)])[0]
		end

		def reset(user)
			puts "USER #{user}"
			bot_session={
				'last_update_id'=>nil,
				'current'=>nil,
				'expected_input'=>"answer",
				'expected_input_size'=>-1,
				'buffer'=>""
			}
			user_settings={
				'blocked'=>{
					'abuse'=>false, # the user has clearly done bad things 
					'not_allowed'=>false, # the information provided by the user do not allow him to participate
					'review'=>false, # the user has done too many bad reviews and cannot review anymore
					'add_candidate'=>false # the user has proposed too many rejected candidates and cannot propose candidates anymore
				},
				'limits'=>{
					'candidate_proposals'=>MAX_CANDIDATES_PROPOSAL,
					'candidate_reviews'=>nil
				},
				'actions'=>{
					'first_help_given'=>false,
					'nb_candidates_proposed'=>0,
					'nb_candidates_reviewed'=>0,
					'beta_nb_position_checked'=>0,
				},
				'roles'=>{
					'betatester'=>false,
					'reviewer'=>false,
				},
				'legal'=>{
					'charte'=>false,
					'can_vote'=>false,
					'email_optin'=>false
				}
			}
			puts "BEFORE #{@users[user[:id]]['session']}"
			self.update_settings(user[:id],user_settings)
			@users[user[:id]]['session']={
				'last_update_id'=>nil,
				'current'=>nil,
				'expected_input'=>"answer",
				'expected_input_size'=>-1,
				'buffer'=>""
			}
			puts "AFTER #{@users[user[:id]]['session']}"
			self.save_user_session(user[:id])
			puts "AFTER DE MEREEEEERDE #{@users[user[:id]]['session']}"
		end

		def get_session(user_id)
			return @users[user_id]['session']
		end

		def clear_session(user_id,key)
			@users[user_id]['session'].delete(key)
		end

		def update_session(user_id,data)
			data.each do |k,v|
				@users[user_id]['session'][k]=v
			end
			return self.get_session(user_id)
		end

		def update_settings(user_id,data)
			@users[user_id]['settings']=Bot.mergeHash(@users[user_id]['settings'],data)
			Bot::Db.query("set_settings",[JSON.dump(@users[user_id]['settings']),user_id]) 
			return @users[user_id]['settings']
		end

		def next_answer(user_id,type,size=-1,callback=nil,buffer="")
			@users[user_id]['session'].merge!({
				'buffer'=>buffer,
				'expected_input'=>type,
				'expected_input_size'=>size,
				'callback'=>callback
			})
		end

		def get(user_info,date)
			res=self.search({
				:by=>"user_id",
				:target=>user_info.id
			})
			if res.num_tuples.zero? then # new user
				slack_msg="Nouveau participant : #{user_info.first_name} #{user_info.last_name} (<https://telegram.me/#{user_info.username}|@#{user_info.username}>)"
				Bot.slack_notification(slack_msg,"inscrits",":telegram:","telegram")
				if date then
					tag={
						'firstname'=>user_info.first_name,
						'lastname'=>user_info.last_name,
						'username'=>user_info.username,
						'register_day'=> Time.at(date).strftime('%Y-%m-%d'),
						'register_week'=> Time.at(date).strftime('%Y-%V'),
						'register_month'=> Time.at(date).strftime('%Y-%m'),
						'beta_waiting_list_pos_checked'=>0,
						'nb_candidates_proposed'=>0
					}
					Democratech::LaPrimaireBot.mixpanel.track(user_info.id,'new_user')
					Democratech::LaPrimaireBot.mixpanel.people.set(user_info.id,tag)
				end
				user=self.add(user_info)
			else
				user=res[0]
			end
			user['session']=JSON.parse(user['session'])
			user['settings']=JSON.parse(user['settings'])
			user[:id]=user['user_id']
			@users[user[:id]]=user
			return user
		end

		def save_user_session(user_id)
			Bot::Db.query("set_session",[JSON.dump(@users[user_id]['session']),user_id]) 
		end

		def already_answered(user_id,update_id)
			return false if update_id==-1 # external command
			session=@users[user_id]['session']
			return true if not session['last_update_id'].nil? and session['last_update_id'].to_i>update_id.to_i
			self.update_session(user_id,{'last_update_id'=>update_id.to_i})
			return false
		end

		def set(user_id,query)
			if query[:using].nil? then
				Bot::Db.query("set_"+query[:set],[query[:value],user_id]) 
			else
				Bot::Db.query("set_"+query[:set]+"_using_"+query[:using][:field],[query[:value],user_id,query[:using][:value]]) 
			end
			@users[user_id][query[:set]]=query[:value] unless query[:set]='session'
		end

		def search(query)
			return Bot::Db.query("get_user_by_"+query[:by],[query[:target]]) 
		end

		def add_to_waiting_list(user)
			return Bot::Db.query("add_to_waiting_list",[user[:id],user['firstname'],user['lastname']]) 
		end

		def remove_from_waiting_list(user)
			return Bot::Db.query("remove_from_waiting_list",[user[:id]]) 
		end

		def get_position_on_wait_list(user_id)
			return Bot::Db.query("get_user_position_in_wait_list",[user_id])[0]
		end

		def beta_code_ok(code)
			res=Bot::Db.query("delete_beta_code",[code])
			ok=!res.num_tuples.zero?
			return ok
		end
	end
end
