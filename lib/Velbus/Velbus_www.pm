# Make an url based on the parameters supplied in the url and extra input parameters
sub www_make_url () {
   my %input ;
   foreach (@_) {
      my @split = split "=" ;
      next if $split[0] eq "" ;
      $input{$split[0]} = $split[1] if @split ;
   }

   my @url ;
   # Loop all CGI params
   foreach my $key (sort keys %{$global{cgi}{params}}) {
      next if $key eq "" ;
      # Overrule parameter if needed
      if ( defined $input{'*'} ) {
         if ( $input{'*'} eq '-' ) {
         } else {
            delete $input{$key} ;
         }
      } elsif ( defined $input{$key} ) {
         if ( $input{$key} eq '-' ) {
         } else {
            push @url, "$key=$input{$key}" ;
            delete $input{$key} ;
         }
      } else {
         push @url, "$key=$global{cgi}{params}{$key}" ;
      }
   }
   foreach my $key (sort keys %input) {
      next if $key eq "" ;
      if ( $input{$key} eq '-' ) {
      } else {
         push @url, "$key=$input{$key}"  ;
      }
   }
   my $url = join "&", @url ;
   return $url ;
}

# Website with some basic menus
sub www_index () {
   my $content ;

   # Starten van html output
   # includen van de nodige files: css en javascript
   $content .= $global{cgi}{CGI}->start_html (
      -title=>"Velbus",
      -style=>[
         {'src'=>"include/jquery.dataTables.min.css"},
      ],
      -script=>[
         { -type=>'text/javascript',
           -src=>'include/jquery-3.3.1.min.js'},
         { -type=>'text/javascript',
           -src=>'include/script.js'},
         { -type=>'text/javascript',
           -src=>'include/jquery.dataTables.min.js'},
      ]
   ) ;

   $content .= "<p>\n" ;
   $content .= "<a href=?".&www_make_url("*=-","appl=print_modules").">Modules on bus</a> || " ;
   $content .= "<a href=?".&www_make_url("*=-","appl=print_channeltags").">Channel tags</a> || " ;
   $content .= "<a href=?".&www_make_url("*=-","appl=print_velbus_protocol").">Velbus protocol</a> || " ;
   $content .= "<a href=?".&www_make_url("*=-","appl=print_velbus_messages").">Velbus messages</a> || " ;
   $content .= "<a href=?".&www_make_url("*=-","appl=openHAB").">openHAB config</a> || " ;
   $content .= "<a href=?".&www_make_url("*=-","appl=scan").">Scan the bus</a> || " ;
   $content .= "<a href=?".&www_make_url("*=-","appl=clear_database").">Clear the database</a> " ;
   $content .= "</p>\n" ;

   if ( $global{cgi}{params}{appl} eq "print_modules" ) {
      if ( defined $global{cgi}{params}{action} ) {
         if ( $global{cgi}{params}{action} eq "status" ) {
            $content .= &www_update_module_status ;
         }
      }
      $content .= &www_print_modules ;
   }
   if ( $global{cgi}{params}{appl} eq "print_channeltags" ) {
      $content .= &www_print_channeltags ;
   }
   if ( $global{cgi}{params}{appl} eq "print_velbus_protocol" ) {
      $content .= &www_print_velbus_protocol ;
   }
   if ( $global{cgi}{params}{appl} eq "print_velbus_messages" ) {
      $content .= &www_print_velbus_messages ;
   }
   if ( $global{cgi}{params}{appl} eq "openHAB" ) {
      $content .= &www_openHAB ;
   }
   if ( $global{cgi}{params}{appl} eq "scan" ) {
      $content .= &www_scan ;
   }
   if ( $global{cgi}{params}{appl} eq "clear_database" ) {
      $content .= &www_clear_database ;
   }
   if ( $global{cgi}{params}{appl} eq "debug" ) {
      $content .= "<pre>\n" ;
      $content .= Dumper {%global} ;
      $content .= "</pre>\n" ;
   }
   $content .= $global{cgi}{CGI}->end_html() ;
   return $content ;
}

# Webservice for remote access
sub www_service () {
   my $sock = &open_socket ;
   my $address ;
   my $Moduletype ; # Type of the module, based on $address

   my %json ;

   # Save the original request parameters
   foreach (keys %{$global{cgi}{params}}) {
      $json{"Req$_"} = $global{cgi}{params}{$_} ;
   }

   # Parse options
   if ( defined $global{cgi}{params}{address} ) {
      $address = $global{cgi}{params}{address} ;
      if ( defined $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{type} and $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{type} ne '' ) {
         $Moduletype = $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{type} ;
      }
   }

   # Put the time on the bus
   if ( defined $global{cgi}{params}{action} and $global{cgi}{params}{action} eq "TimeSync" ) {
      $json{action} = $global{cgi}{params}{action} ;
      &broadcast_datetime($sock) ;
      $json = "" ;
   }

   # Set memo text: only for VMBGPOD
   if ( defined $global{cgi}{params}{action} and $global{cgi}{params}{action} eq "Memo" ) {
      $json{action} = $global{cgi}{params}{action} ;
      if ( defined $Moduletype and $Moduletype eq "28" ) {
         if ( defined $global{cgi}{params}{text} ) {
            &send_memo ($sock, $address, $global{cgi}{params}{text}) ;
            $json{Text} = $global{cgi}{params}{text} ;
         } else {
            $json{Error} = "NO_TEXT" ;
         }
      } else {
         $json{Error} = "NO_MODULETYPE" ;
      }
   }

   # The rest is for getting and setting.
   if ( defined $global{cgi}{params}{type} ) {
      my $type = $global{cgi}{params}{type} ;

      # 1: if we have a type, it should be defined in $global{ActionType}
      if ( ! defined $global{ActionType}{$type} ) {
         $json{Error} = "UNSUPPORTED_TYPE" ;

      # 2: we need an address
      } elsif ( ! defined $global{cgi}{params}{address} ) {
         $json{Error} = "NO_ADDRESS" ;

      # 3: we need a module type (based on parameter address)
      } elsif ( ! defined $Moduletype ) {
         $json{Error} = "NO_MODULETYPE" ;

      # 4: the module type should be supported for the type
      } elsif ( ! defined $global{ActionType}{$type}{Module}{$Moduletype} ) {
         $json{Error} = "MODULETYPE_NOT_SUPPORTED" ;

      # 5: we also need an action
      } elsif ( ! defined $global{cgi}{params}{action} ) {
         $json{Error} = "NO_ACTION" ;

      # 6: If action = Set we need a value
      } elsif ( $global{cgi}{params}{action} eq "Set" and ! defined $global{cgi}{params}{value} ) {
         $json{Error} = "NO_VALUE_FOR_SET" ;

      } else {
         my $action = $global{cgi}{params}{action} ;

         # For blinds, we need to set action based on value
         if ( $type eq "Blind" ) {
            if ( $global{cgi}{params}{value} eq "UP" ) {
               $action = "Up" ;
            } elsif ( $global{cgi}{params}{value} eq "DOWN" ) {
               $action = "Down" ;
            } elsif ( $global{cgi}{params}{value} eq "STOP" ) {
               $action = "Stop" ;
            } elsif ( $global{cgi}{params}{value} =~ /(\d+)/ ) {
               $action = "Pos" ;
            }
         }

         # 7: the action should be supported for the type (Get is always valid)
         if ( ! ( $action =~ /^Get/ or defined $global{ActionType}{$type}{Command}{$action} ) ) {
            $json{Error} = "ACTION_NOT_SUPPORTED" ;

         } else {
            # 8: the command used in the action should exist for the module type
            my $command = $global{ActionType}{$type}{Command}{$action} ;
            if ( ! ( $action =~ /^Get/ or defined $global{Cons}{ModuleTypes}{$Moduletype}{Messages}{$command}{Name} ) ) {
               $json{Error} = "COMMAND_NOT_SUPPORTED" ;

            } else {
               $json{action} = $action ;

               # Get the current temperature: touch panels & outdoor sensor
               if ( $type eq "Temperature" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_info where `address`='$address'","data") ;
                  $json{Name}   = $data{TempSensor}{value}  if defined $data{TempSensor} ;
                  $json{Status} = $data{Temperature}{value} if defined $data{Temperature} ;
               }

               # Get/Set the Cooler/Heater target temperature: touch panels
               if ( $type eq "TemperatureTarget" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_info where `address`='$address'","data") ;
                  $json{Name} = $data{TempSensor}{value}  if defined $data{TempSensor} ;

                  if ( $action eq "Set" ) {
                     if ( $global{cgi}{params}{value} =~ /^\d+\.\d+$/ or $global{cgi}{params}{value} =~ /^\d+$/ ) {
                        &set_temperature ($sock, $address, $global{cgi}{params}{value}) ;
                        $json{Status} = $global{cgi}{params}{value} ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='00'","data") ;
                     if ( defined $data{'Current temperature set'} ) {
                        $json{Status} = $data{'Current temperature set'}{value} ;
                     }
                  }
               }

               # Get/Set heating or cooling: touch panels
               if ( $type eq "TemperatureCoHeMode" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_info where `address`='$address'","data") ;
                  $json{Name}   = $data{TempSensor}{value}  if defined $data{TempSensor} ;

                  if ( $action eq "Set" ) {
                     if ( $global{cgi}{params}{value} eq "1" or $global{cgi}{params}{value} eq "0" ) {
                        &set_temperature_cohe_mode ($sock, $address, $global{cgi}{params}{value}) ;
                        $json{Status} = $global{cgi}{params}{value} ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='00'","data") ;
                     if ( defined $data{'Temperature CoHe mode'} ) {
                        if ( $data{'Temperature CoHe mode'}{value} =~ /cooler/i ) {
                           $json{Status} = 1 ;
                        } elsif ( $data{'Temperature CoHe mode'}{value} =~ /heater/i ) {
                           $json{Status} = 0 ;
                        }
                     }
                  }
               }

               # Get/Set the Heater mode: touch panels
               if ( $type eq "TemperatureMode" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_info where `address`='$address'","data") ;
                  $json{Name}   = $data{TempSensor}{value}  if defined $data{TempSensor} ;

                  if ( $action eq "Set" ) {
                     if ( $global{cgi}{params}{value} eq "1" or $global{cgi}{params}{value} eq "2" or $global{cgi}{params}{value} eq "3" or $global{cgi}{params}{value} eq "4" ) {
                        &set_temperature_mode ($sock, $address, $global{cgi}{params}{value}) ;
                        $json{Status} = $global{cgi}{params}{value} ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='00'","data") ;
                     if ( defined $data{'Temperature mode'} ) {
                        if (      $data{'Temperature mode'}{value} =~ /comfort/i ) {
                           $json{Status} = 1 ;
                        } elsif ( $data{'Temperature mode'}{value} =~ /day/i ) {
                           $json{Status} = 2 ;
                        } elsif ( $data{'Temperature mode'}{value} =~ /night/i ) {
                           $json{Status} = 3 ;
                        } elsif ( $data{'Temperature mode'}{value} =~ /safe/i ) {
                           $json{Status} = 4 ;
                        }
                     }
                  }
               }

               # Get/Set button: touch, input, sensors, ...
               if ( $type eq "Switch" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='$global{cgi}{params}{channel}'","data") ;
                  $json{Name}   = $data{Name}{value}   if defined $data{Name};

                  if ( $action eq "Set" ) {
                     if ( $global{cgi}{params}{value} eq "ON" ) {
                        &button_pressed ($sock, $address, $global{cgi}{params}{channel}) ;
                        $json{Status} = $global{cgi}{params}{value} ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     $json{Status} = $data{Button}{value} if defined $data{Button} ;
                  }
               }

               # Get/Set Dimmer level
               if ( $type eq "Dimmer" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='$global{cgi}{params}{channel}'","data") ;
                  $json{Name}   = $data{Name}{value}   if defined $data{Name} ;

                  if ( $action eq "Set" ) {
                     if ( $global{cgi}{params}{value} eq "ON" or $global{cgi}{params}{value} eq "OFF" or $global{cgi}{params}{value} =~ /^\d+$/ ) {
                        $global{cgi}{params}{value} = "100" if $global{cgi}{params}{value} eq "ON" ;
                        $global{cgi}{params}{value} = "0"   if $global{cgi}{params}{value} eq "OFF" ;
                        &dim_value ($sock, $address, $global{cgi}{params}{channel}, $global{cgi}{params}{value}) ;
                        $json{Status} = $global{cgi}{params}{value} ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     $json{Status} = $data{Dimmer}{value} if defined $data{Dimmer}{value} ;
                  }
               }

               # Get/Set Blind positoin
               if ( $type eq "Blind" ) {
                  if ( $Moduletype eq "03" ) {
                     $global{cgi}{params}{channel} = "0x03" ;
                  }
                  if ( $Moduletype eq "09" ) {
                     if ( $global{cgi}{params}{channel} eq "01" ) {
                        $global{cgi}{params}{channel} = "0x03" ;
                     }
                     if ( $global{cgi}{params}{channel} eq "02" ) {
                        $global{cgi}{params}{channel} = "0x0C" ;
                     }
                  }

                  my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='$global{cgi}{params}{channel}'","data") ;
                  $json{Name}   = $data{Name}{value}   if defined $data{Name}{value} ;

                  # For blinds, we use {params}{action} and not $action because we filled in $action based on the {params}{value}
                  # This is needed because not all commands are supported by all blind modules.
                  if ( $global{cgi}{params}{action} eq "Set" ) {
                     if ( $global{cgi}{params}{value} eq "UP" ) {
                        &blind_up ($sock, $address, $global{cgi}{params}{channel}) ;
                     } elsif ( $global{cgi}{params}{value} eq "DOWN" ) {
                        &blind_down ($sock, $address, $global{cgi}{params}{channel}) ;
                     } elsif ( $global{cgi}{params}{value} eq "STOP" ) {
                        &blind_stop ($sock, $address, $global{cgi}{params}{channel}) ;
                     } elsif ( $global{cgi}{params}{value} =~ /(\d+)/ ) {
                        &blind_pos ($sock, $address, $global{cgi}{params}{channel}, $1) ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     $json{Status} = $data{Position}{value} if defined $data{Position}{value} ;
                  }
               }

               # Get/Set Relay status
               if ( $type eq "Relay" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='$global{cgi}{params}{channel}'","data") ;
                  $json{Name} = $data{Name}{value} if defined $data{Name} ;

                  if ( $action eq "Set" ) {
                     if ( $global{cgi}{params}{value} eq "ON" ) {
                        &relay_on ($sock, $address, $global{cgi}{params}{channel}) ;
                        $json{Status} = "ON" ;
                     } elsif ( $global{cgi}{params}{value} eq "OFF" ) {
                        &relay_off ($sock, $address, $global{cgi}{params}{channel}) ;
                        $json{Status} = "OFF" ;
                     } else {
                        $json{Error} = "INCORRECT_VALUE" ;
                     }
                  } else {
                     if ( defined $data{'Relay status'} ) {
                        if ( $data{'Relay status'}{value}      eq "Relay channel off" ) {
                           $json{Status} = "OFF" ;
                        } elsif ( $data{'Relay status'}{value} eq "Relay channel on" ) {
                           $json{Status} = "ON" ;
                        }
                     }
                  }
               }

               # Get SensorNumber : only for VMB4AN
               if ( $type eq "SensorNum" ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='$global{cgi}{params}{channel}'","data") ;
                  $json{Status} = $data{SensorNumber}{value} if defined $data{SensorNumber} ;
               }

               # Get Counter : only for VMB7IN
               if ( $type eq "Counter" and ( $action eq "GetCounter" or $action eq "GetCounterRaw" or $action eq "GetCounterCurrent" or $action eq "GetDivider" ) ) {
                  my %data = &fetch_data ($global{dbh},"select * from modules_channel_info where `address`='$address' and `channel`='$global{cgi}{params}{channel}'","data") ;

                  if ( $action eq "GetCounter" ) {
                     $json{Status} = $data{Counter}{value}        if defined $data{Counter} ;
                  } elsif ( $action eq "GetCounterCurrent" ) {
                     $json{Status} = $data{CounterCurrent}{value} if defined $data{CounterCurrent} ;
                  } elsif ( $action eq "GetCounterRaw" ) {
                     $json{Status} = $data{CounterRaw}{value}     if defined $data{CounterRaw} ;
                  } else {
                     $json{Status} = $data{Divider}{value}        if defined $data{Divider} ;
                  }
               }

               $json{Error} = "NO_INFO" if ! defined $json{Status} ;
            }
         }
      }
   }

   return %json ;
}

sub www_print_modules () {
   my $html ;
   $html .= "<h1>All modules on bus (<a href=\"?".&www_make_url("action=status")."\">refresh status</a>)</h1>\n" ;

   my %data ;

   # Loop all module types
   foreach my $type (sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}})) {
#next if $type ne '28' ;

      # Loop all modules
      foreach my $address ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}{$type}{ModuleList}}) ) {
         foreach my $Key (keys (%{$global{Vars}{Modules}{Address}{$address}{ModuleInfo}}) ) {
            if ( $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{$Key} ne "" ) {
               $global{Vars}{Modules}{PerType}{$type}{ModuleInfoKey}{$Key} = "" ; # To get a list of info per module
            }
         }

         # If the module has sub addresses, take them in consideration
         if ( defined $global{Vars}{Modules}{Address}{$address}{ChannelInfo} ) {
            foreach my $Channel ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{Address}{$address}{ChannelInfo}}) ) {
               foreach my $Key ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}}) ) {
                  if ( $Channel eq "00" ) { # Channel 00 contains info about the module itself
                     if ( $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{value} ne "" ) {
                        $global{Vars}{Modules}{PerType}{$type}{ModuleInfoKey}{$Key} = "" ; # To get a list of info per module
                        $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{$Key} = $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{value} ;
                     }
                  } else {
                     $global{Vars}{Modules}{PerType}{$type}{ChannelInfoKey}{$Key} = "" ; # To get a list of info per channel
                     $global{Vars}{Modules}{PerType}{$type}{ChannelList}{$Channel} = "" ; # To get a list of the channels
                  }
               }
            }
         }
      }
   }

   foreach my $status (sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerStatus}})) {
      next if $status eq "Start scan" ;

      $html .= "<h2>Status: $status</h2>\n" ;

      my $table ;
      $table .= "<table border=1>\n" ;
      $table .= "<thead>\n" ;
      $table .= "  <tr>\n" ;
      $table .= "    <th>Address</th>\n" ;
      $table .= "    <th>Type</th>\n" ;
      $table .= "    <th>Info</th>\n" ;
      $table .= "    <th>Name</th>\n" ;
      $table .= "    <th>Build</th>\n" ;
      $table .= "    <th>MemoryKey</th>\n" ;
      $table .= "    <th>MemoryMap</th>\n" ;
      $table .= "    <th>Date</th>\n" ;
      $table .= "    <th>Action</th>\n" ;
      $table .= "  </tr>\n" ;
      $table .= "</thead>\n" ;

      $table .= "<tbody>\n" ;

      my $mail_body ;
      $mail_body .= "Hi,\n" ;
      $mail_body .= "\n" ;
      $mail_body .= "This information will be used to further improve the velserver scripts. See https://github.com/StefCoene/velserver.\n" ;
      $mail_body .= "\n" ;
      $mail_body .= "If something is not working and/or everything is working fine, you can specify it in this email.\n" ;
      $mail_body .= "I don't have all modules so for some modules I have to rely on the protocol files to get them supported.\n" ;
      $mail_body .= "\n" ;
      $mail_body .= "\n" ;
      $mail_body .= "Stef Coene\n" ;
      $mail_body .= "\n" ;
      $mail_body .= "address;type;ModuleName;Build;MemoryKey;MemoryMap;\n" ;

      foreach my $address ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerStatus}{$status}{ModuleList}}) ) {
         my $type = $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{'type'} ; # Handier var
         my $MemoryKey = &module_find_MemoryKey ($address, $type) ; # Handier var
         my $MemoryMap = $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{MemoryMap} ;
         $table .= "  <tr>\n" ;
         if ( defined $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{SubAddr} ) {
            $table .= "    <th>$address ($global{Vars}{Modules}{Address}{$address}{ModuleInfo}{SubAddr})</th>\n" ;
         } else {
            $table .= "    <th>$address</th>\n" ;
         }
         $mail_body .= "$address;" ;
         $table .= "    <td>$global{Cons}{ModuleTypes}{$type}{Type} ($type)</td>\n" ;
         $mail_body .= "$type;" ;
         $table .= "    <td>$global{Cons}{ModuleTypes}{$type}{Info}</td>\n" ;
         $table .= "    <td>$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{ModuleName}</td>\n" ;
         $mail_body .= "$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{ModuleName};" ;
         $table .= "    <td>$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{BuildYear}$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{BuildWeek}</td>\n" ;
         $mail_body .= "$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{BuildYear}$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{BuildWeek};" ;

         if ( defined $MemoryKey ) {
            $table .= "    <td>$MemoryKey</td>\n" ;
            $mail_body .= "$MemoryKey;" ;
         } else {
            $table .= "    <td>-</td>\n" ;
            $mail_body .= ";" ;
         }
         if ( defined $MemoryMap ) {
            if ( defined $global{Cons}{ModuleTypes}{$type}{Memory}{$MemoryMap}{ModuleName}) {
               $table .= "    <td>$MemoryMap</td>\n" ;
               $mail_body .= "$MemoryMap;" ;
            } else {
               $table .= "    <td>$MemoryMap: not found?</td>\n" ;
               $mail_body .= "$MemoryMap not found;" ;
            }
         } else {
            $table .= "    <td>No MemoryMap found!</td>\n" ;
            $mail_body .= ";" ;
         }
         $table .= "    <td>$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{'date'}</td>\n" ;
         $table .= "    <td><a href=\"?".&www_make_url("action=status","address=$address")."\">refresh status</a></td>\n" ;
         $table .= "  </tr>\n" ;
         $mail_body .= "\n" ;
      }
      $table .= "</tbody>\n" ;
      $table .= "</table>\n" ;

      $mail_body =~ s/\n/%0D%0A/g ;
      $html .= "<p>Do you want to help? Send me <a href=\"mailto:velserver\@docum.org?subject=velserver detected modules&body=$mail_body\">an email</a> with the content of this table. Especially if there is an issue with the MemoryKey and MemoryMap column</p>\n" ;
      $html .= $table ;
   }

   foreach my $type (sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}})) {
      $html .= "<h2>$global{Cons}{ModuleTypes}{$type}{Type} ($type) $global{Cons}{ModuleTypes}{$type}{Info}</h2>\n" ;
      $html .= "<h3>Module info</h3>\n" ;

      $html .= "<table border=1>\n" ;
      $html .= "<thead>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <th>Address</th>\n" ;
      foreach my $Key (sort keys %{$global{Vars}{Modules}{PerType}{$type}{ModuleInfoKey}} ) {
         $html .= "    <th>$Key</th>\n" ;
      }
      $html .= "    <th>Action</th>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;

      $html .= "<tbody>\n" ;

      foreach my $address ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}{$type}{ModuleList}}) ) {
         $html .= "  <tr>\n" ;
         $html .= "    <th>$address</th>\n" ;
         foreach my $Key (sort keys %{$global{Vars}{Modules}{PerType}{$type}{ModuleInfoKey}} ) {
            $html .= "    <td>$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{$Key}</td>\n" ;
            #$html .= "    <td>$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{value}<br />$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{data}</td>\n" ;
         }
         $html .= "    <td><a href=\"?".&www_make_url("action=status","address=$address")."\">refresh status</a></td>\n" ;

         $html .= "  </tr>\n" ;
      }

      $html .= "</tbody>\n" ;
      $html .= "</table>\n" ;

      if ( %{$global{Vars}{Modules}{PerType}{$type}{ChannelInfoKey}} ) {
         $html .= "<h3>Channel info</h3>\n" ;
         $html .= "<table border=1>\n" ;
         $html .= "<thead>\n" ;
         $html .= "  <tr>\n" ;
         $html .= "    <th>Address</th>\n" ;
         $html .= "    <th>Channel</th>\n" ;
         foreach my $Key (sort keys %{$global{Vars}{Modules}{PerType}{$type}{ChannelInfoKey}} ) {
            $html .= "    <th>$Key</th>\n" ;
         }
         $html .= "    <th>Action</th>\n" ;
         $html .= "  </tr>\n" ;
         $html .= "</thead>\n" ;

         $html .= "<tbody>\n" ;

         foreach my $address ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}{$type}{ModuleList}}) ) {
            $html .= "  <tr>\n" ;
            $html .= "    <th rowspan=ROWSPAN>$address</th>\n" ;
            $ROWSPAN = 0 ;
            foreach my $Channel (sort keys %{$global{Vars}{Modules}{PerType}{$type}{ChannelList}} ) {
               $html .= "  <tr>\n" if $ROWSPAN ne "0" ;
               $html .= "    <td>$Channel</td>\n" ;
               foreach my $Key (sort keys %{$global{Vars}{Modules}{PerType}{$type}{ChannelInfoKey}} ) {
                  $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{value} =~ s/;/<br \/>/g ;
                  $html .= "    <td>$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{value}<br />$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{date}</td>\n" ;
               }
               $html .= "    <td><a href=\"?".&www_make_url("action=status","address=$address","channel=$Channel")."\">refresh status</a></td>\n" ;

               $html .= "  </tr>\n" if $ROWSPAN ne "0" ;
               $ROWSPAN ++ ;
            }
            $html .= "  </tr>\n" ;
            $html =~ s/ROWSPAN/$ROWSPAN/g ;
         }

         $html .= "</tbody>\n" ;
         $html .= "</table>\n" ;
      }
   }

   #$html .= "<pre>\n" ;
   #$html .= Dumper \%{$global{Vars}{Modules}{PerType}} ;
   #$html .= Dumper \%{$global{Vars}} ;
   #$html .= Dumper \%data ;
   #$html .= "</pre>\n" ;
   return $html ;
}

sub www_print_channeltags () {
   my $html ;
   $html .= "<h1>All modules and channels on the bus</h1>\n" ;

   my %data ;

   # Processing the selected tags
   foreach my $param (sort keys %{$global{cgi}{params}} ) {
      if ( $param =~ /Tag::(..)::(..)/ ) {
         my $Address  = $1 ;
         my $Channel = $2 ;
         &update_modules_channel_info ($Address, $Channel, "Tag", $global{cgi}{params}{$param}) ;
      }
   }

   $html .= $global{cgi}{CGI}->start_form() ;
   $html .= $global{cgi}{CGI}->submit() ;
   $html .= $global{cgi}{CGI}->hidden(-name=>'appl',$global{cgi}{params}{appl}) ;

   # Loop all module types
   foreach my $type (sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}})) {

      # Loop all modules
      foreach my $address ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}{$type}{ModuleList}}) ) {
         foreach my $Key (keys (%{$global{Vars}{Modules}{Address}{$address}{ModuleInfo}}) ) {
            if ( $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{$Key} ne "" ) {
               $global{Vars}{Modules}{PerType}{$type}{ModuleInfoKey}{$Key} = "" ; # To get a list of info per module
            }
         }

         # If the module has sub addresses, take them in consideration
         if ( defined $global{Vars}{Modules}{Address}{$address}{ChannelInfo} ) {
            foreach my $Channel ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{Address}{$address}{ChannelInfo}}) ) {
               foreach my $Key ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}}) ) {
                  if ( $Channel eq "00" ) { # Channel 00 contains info about the module itself
                     if ( $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{value} ne "" ) {
                        $global{Vars}{Modules}{PerType}{$type}{ModuleInfoKey}{$Key} = "" ; # To get a list of info per module
                        $global{Vars}{Modules}{Address}{$address}{ModuleInfo}{$Key} = $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{$Key}{value} ;
                     }
                  } else {
                     $global{Vars}{Modules}{PerType}{$type}{ChannelInfoKey}{$Key} = "" ; # To get a list of info per channel
                     $global{Vars}{Modules}{PerType}{$type}{ChannelList}{$Channel} = "" ; # To get a list of the channels
                  }
               }
            }
         }
      }
   }

   foreach my $type (sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}})) {
      $html .= "<h2>$global{Cons}{ModuleTypes}{$type}{Type} ($type) $global{Cons}{ModuleTypes}{$type}{Info}</h2>\n" ;

      if ( %{$global{Vars}{Modules}{PerType}{$type}{ChannelInfoKey}} ) {
         $html .= "<h3>Channel tags</h3>\n" ;
         $html .= "<table border=1>\n" ;
         $html .= "<thead>\n" ;
         $html .= "  <tr>\n" ;
         $html .= "    <th>Address</th>\n" ;
         $html .= "    <th>Module Name</th>\n" ;
         $html .= "    <th>Channel</th>\n" ;
         $html .= "    <th>Channel Name</th>\n" ;
         $html .= "    <th>Tag</th>\n" ;
         $html .= "  </tr>\n" ;
         $html .= "</thead>\n" ;

         $html .= "<tbody>\n" ;

         foreach my $address ( sort {$a cmp $b} keys (%{$global{Vars}{Modules}{PerType}{$type}{ModuleList}}) ) {
            $html .= "  <tr>\n" ;
            $html .= "    <th rowspan=ROWSPAN>$address</th>\n" ;
            $html .= "    <th rowspan=ROWSPAN>$global{Vars}{Modules}{Address}{$address}{ModuleInfo}{ModuleName}</th>\n" ;
            $ROWSPAN = 0 ;
            foreach my $Channel (sort keys %{$global{Vars}{Modules}{PerType}{$type}{ChannelList}} ) {
               $html .= "  <tr>\n" if $ROWSPAN ne "0" ;
               $html .= "    <td>$Channel</td>\n" ;
               $html .= "    <td>$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{Name}{value}<br />$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{Name}{date}</td>\n" ;

               $html .= "    <td>" ;
               if ( $global{Cons}{ModuleTypes}{$type}{Channels}{$Channel}{Type} eq "Relay" or
                    $global{Cons}{ModuleTypes}{$type}{Channels}{$Channel}{Type} eq "Button" or
                    $global{Cons}{ModuleTypes}{$type}{Channels}{$Channel}{Type} eq "Dimmer" ) {
                  if ( ! defined $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{Tag}{value} or
                       $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{Tag}{value} eq "" ) {
                     $global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{Tag}{value} = '__NoTag__' ;
                  }
                  $html .= $global{cgi}{CGI}->scrolling_list(
                        -name=>"Tag::$address::$Channel",
                        -size=>1,
                        -values=>['Lighting', 'Switchable', '__NoTag__'],
                        -default=>[$global{Vars}{Modules}{Address}{$address}{ChannelInfo}{$Channel}{Tag}{value}]
                     ) ;
               } else {
                  $html .= "&nbsp;" ;
               }
               $html .= "</td>\n" ;

               $html .= "  </tr>\n" if $ROWSPAN ne "0" ;
               $ROWSPAN ++ ;
            }
            $html .= "  </tr>\n" ;
            $html =~ s/ROWSPAN/$ROWSPAN/g ;
         }

         $html .= "</tbody>\n" ;
         $html .= "</table>\n" ;
      }
   }

   $html .= $global{cgi}{CGI}->end_form() ;
   return $html ;
}

sub www_print_velbus_messages () {
   $html .= "<h1>Velbus messages</h1>\n" ;
   if ( defined $global{cgi}{params}{Message} ) {
      $html .= &www_print_velbus_messages_print_message($global{cgi}{params}{Message}) ;
   } else {
      $html .= &www_print_velbus_messages_print_messages ;
   }
   return $html ;
}

sub www_print_velbus_messages_print_message () {
   my $Message = $_[0] ;
   my $html ;
   my %data =&www_process_messages ;
   if ( defined $data{BroadCast}{$Message} ) {
      $html .= "<h2>Broadcast message: $Message</h2>\n" ;
      $Info = $data{BroadCast}{$Message}{Info} ;
      $Info =~ s/;/<br \/>/g ;
      $Name = $data{BroadCast}{$Message}{Name} ;
      $Name =~ s/;/<br \/>/g ;
      $Prio = $data{BroadCast}{$Message}{Prio} ;

      $html .= "<table border=1 class=\"\">\n" ;
      $html .= "<thead>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <th>Message</th>\n" ;
      $html .= "    <th>Name</th>\n" ;
      $html .= "    <th>Info</th>\n" ;
      $html .= "    <th>Prio</th>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;

      $html .= "<tbody>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <td>$Message</td>\n" ;
      $html .= "    <td>$Name</td>\n" ;
      $html .= "    <td>$Info</td>\n" ;
      $html .= "    <td>$Prio</td>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;
      $html .= "</table>\n" ;

   } elsif ( defined $data{Module}{$Message} ) {
      $html .= "<h2>Non-broadcast message: $Message</h2>\n" ;
      my $Name = join ";", sort keys %{$data{Module}{$Message}{Name}} ;
      $Name =~ s/;/<br \/>/g ;
      my $Info = join ";", sort keys %{$data{Module}{$Message}{Info}} ;
      $Info =~ s/;/<br \/>/g ;
      my $Prio = join ";", sort keys %{$data{Module}{$Message}{Prio}} ;

      $html .= "<table border=1 class=\"\">\n" ;
      $html .= "<thead>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <th>Message</th>\n" ;
      $html .= "    <th>Modules</th>\n" ;
      $html .= "    <th>Name</th>\n" ;
      $html .= "    <th>Info</th>\n" ;
      $html .= "    <th>Prio</th>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;

      $html .= "<tbody>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <td>$Message</td>\n" ;
      $html .= "    <td>" ;
      foreach my $ModuleType (sort keys %{$data{Module}{$Message}{ModuleType}} ) {
         $html .= "<a href=?".&www_make_url("appl=print_velbus_protocol","ModuleType=$ModuleType").">$global{Cons}{ModuleTypes}{$ModuleType}{Type} ($ModuleType)</a><br />" ;
      }
      $html .= "</td>\n" ;
      $html .= "    <td>$Name</td>\n" ;
      $html .= "    <td>$Info</td>\n" ;
      $html .= "    <td>$Prio</td>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;
      $html .= "</table>\n" ;

      foreach my $ModuleType (sort keys %{$data{Module}{$Message}{ModuleType}} ) {
         if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data} ) {
            $html .= "<h3><a href=?".&www_make_url("appl=print_velbus_protocol","ModuleType=$ModuleType").">$global{Cons}{ModuleTypes}{$ModuleType}{Type} ($ModuleType) = $global{Cons}{ModuleTypes}{$ModuleType}{Info}</a></h3>\n" ;
            foreach my $byte (sort keys %{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}}) {
               if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}{Name} ) {
                  $html .= "<h4>byte: $byte = $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}{Name}</h4>\n" ;
               } else {
                  $html .= "<h4>byte: $byte</h4>\n" ;
               }
               if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}{Match} ) {
                  foreach my $Match (sort keys %{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}{Match}}) {
                     $html .= "Match: $Match\n" ;
                     foreach my $Key (sort keys %{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}{Match}{$Match}}) {
                        $html .= " -> $Key: $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}{Match}{$Match}{$Key}\n" ;
                     }
                     $html .= "<br />\n" ;
                  }
               }
               #$html .= "<pre>\n" ;
               #$html .= Dumper \%{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$byte}} ;
               #$html .= "</pre>\n" ;
            }
         } else {
            $html .= "<h3><a href=?".&www_make_url("appl=print_velbus_protocol","ModuleType=$ModuleType").">$global{Cons}{ModuleTypes}{$ModuleType}{Type} ($ModuleType) = $global{Cons}{ModuleTypes}{$ModuleType}{Info}</a>: not supported</h3>\n" ;
         }
      }
   } elsif ( defined $Message ) {
      $html .= "<h2>No info found for: $Message</h2>\n" ;
   }

   $html .= "<pre>\n" ;
   #$html .= Dumper \%global ;
   #$html .= Dumper \%{$data{Module}{$Message}} ;
   $html .= "</pre>\n" ;
   return $html ;
}

sub www_print_velbus_messages_print_messages () {
   my $html ;

   my %data =&www_process_messages ;

   $html .= "<h2>Broadcast messages</h2>\n" ;
   $html .= "<table border=1 class=\"datatable\">\n" ;
   $html .= "<thead>\n" ;
   $html .= "  <tr>\n" ;
   $html .= "    <th>Message</th>\n" ;
   $html .= "    <th>Name</th>\n" ;
   $html .= "    <th>Info</th>\n" ;
   $html .= "    <th>Prio</th>\n" ;
   $html .= "  </tr>\n" ;
   $html .= "</thead>\n" ;

   $html .= "<tbody>\n" ;
   foreach my $Message (sort  {$a cmp $b} keys %{$data{BroadCast}}) {
      my $Name = $data{BroadCast}{$Message}{Name} ; # Handier var
      my $Info = $data{BroadCast}{$Message}{Info} ; # Handier var
      my $Prio = $data{BroadCast}{$Message}{Prio} ; # Handier var
      $html .= "  <tr>\n" ;
      $html .= "    <th><a href=?".&www_make_url("appl=print_velbus_messages", "Message=$Message").">$Message</a></th>\n" ;
      $Name =~ s/COMMAND_//g ;
      $html .= "    <td>$Name</td>\n" ;
      $Info =~ s/;/<br \/>/g ;
      $html .= "    <td>$Info</td>\n" ;
      $html .= "    <td>$Prio</td>\n" ;
      $html .= "  </tr>\n" ;
   }
   $html .= "</tbody>\n" ;
   $html .= "</table>\n" ;

   foreach my $type (sort keys %{$data{PerType}}) {
      $html .= "<h2>Module messages: type $type</h2>\n" ;
      $html .= "<table border=1 class=\"datatable\">\n" ;
      $html .= "<thead>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <th>Message</th>\n" ;
      $html .= "    <th>Name</th>\n" ;
      $html .= "    <th>Module</th>\n" ;
      $html .= "    <th>Info</th>\n" ;
      $html .= "    <th>Prio</th>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;

      $html .= "<tbody>\n" ;
      foreach my $Message (sort @{$data{PerType}{$type}}) {
         my $Name = join ";", sort keys %{$data{Module}{$Message}{Name}} ;
         $Name =~ s/;/<br \/>/g ;
         my $Info = join ";", sort keys %{$data{Module}{$Message}{Info}} ;
         $Info =~ s/;/<br \/>/g ;
         my $Prio = join ";", sort keys %{$data{Module}{$Message}{Prio}} ;

         $html         .= "  <tr>\n" ;
         $html         .= "    <th><a href=?".&www_make_url("appl=print_velbus_messages", "Message=$Message").">$Message</a></th>\n" ;
         $Name =~ s/COMMAND_//g ;
         $html         .= "    <td>$Name</td>\n" ;
         $html         .= "    <td>\n" ;
         foreach my $ModuleType (sort keys %{$data{Module}{$Message}{ModuleType}} ) {
            $html .= "<a href=?".&www_make_url("appl=print_velbus_protocol","ModuleType=$ModuleType").">$global{Cons}{ModuleTypes}{$ModuleType}{Type} ($ModuleType)</a><br />" ;
         }
         $html         .= "    </td>\n" ;
         $html         .= "    <td>$Info</td>\n" ;
         $html         .= "    <td>$Prio</td>\n" ;
         $html         .= "  </tr>\n" ;
      }
      $html .= "</tbody>\n" ;
      $html .= "</table>\n" ;
   }

   return $html ;
}

sub www_print_velbus_protocol () {
   my $html ;
   $html .= "<h1>Velbus protocol</h1>\n" ;
   $html .= "<p>This is a list of all modules based on the published protocol files. For each module, the protocol pdf file is converted to txt and parsed. The script can found in bin/pdf2txt.pl and the result is lib/Velbus/Velbus_data_protocol_auto.pm.<br />.</p>\n" ;
   if ( defined $global{cgi}{params}{ModuleType} ) {
      $html .= &www_print_velbus_protocol_print_moduleType($global{cgi}{params}{ModuleType}) ;
   } else {
      $html .= &www_print_velbus_protocol_print_modules ;
   }
   return $html ;
}

sub www_print_velbus_protocol_print_moduleType () {
   my $ModuleType = $_[0] ;
   $html .= "<h2>$global{Cons}{ModuleTypes}{$ModuleType}{Type} ($ModuleType): $global{Cons}{ModuleTypes}{$ModuleType}{Info}</h2>\n" ;

   if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Channels} ) {
      $html .= "<h3>Available channels on module (manual defined in lib/Velbus/Velbus_data_protocol.pm)</h3>\n" ;
      $html .= "<table border=1 class=\"datatable\">\n" ;
      $html .= "<thead>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <th>Channel</th>\n" ;
      $html .= "    <th>Name</th>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;

      $html .= "<tbody>\n" ;
      foreach my $Channel ( sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}{$ModuleType}{Channels}}) ) {
         $html .= "  <tr>\n" ;
         $html .= "    <th>$Channel</th>\n" ;
         $html .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Channels}{$Channel}{Name}</td>\n" ;
         $html .= "  </tr>\n" ;
      }
      $html .= "</tbody>\n" ;
      $html .= "</table>\n" ;
   }

   if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Messages} ) {
      $html .= "<h3>Possible messages (read from lib/Velbus/Velbus_data_protocol_auto.pm)</h3>\n" ;
      $html .= "<table border=1 class=\"datatable\">\n" ;
      $html .= "<thead>\n" ;
      $html .= "  <tr>\n" ;
      $html .= "    <th>Message</th>\n" ;
      $html .= "    <th>Name</th>\n" ;
      $html .= "    <th>Info</th>\n" ;
      $html .= "    <th>Prio</th>\n" ;
      $html .= "  </tr>\n" ;
      $html .= "</thead>\n" ;

      $html .= "<tbody>\n" ;
      my $html2 ;
      my %Messages ;

      foreach my $Message ( sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}}) ) {
         $html .= "  <tr>\n" ;
         $html .= "    <th>$Message</th>\n" ;
         $html .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Name}</td>\n" ;
         $html .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Info}</td>\n" ;
         $html .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Prio}</td>\n" ;
         $html .= "  </tr>\n" ;

         if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data} ) {
            $html2 .= "<h4>Databytes for message $Message ($global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Name}: $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Info})</h4>\n" ;
            $html2 .= "<table border=1 class=\"datatable\">\n" ;
            $html2 .= "<thead>\n" ;
            $html2 .= "  <tr>\n" ;
            $html2 .= "    <th>DataByte</th>\n" ;
            $html2 .= "    <th>Name</th>\n" ;
            $html2 .= "    <th>Type</th>\n" ;
            $html2 .= "    <th>Parser: result</th>\n" ;
            $html2 .= "  </tr>\n" ;
            $html2 .= "</thead>\n" ;

            $html2 .= "<tbody>\n" ;
            foreach my $DataByte (  sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}}) ) {
               $html2 .= "  <tr>\n" ;
               $html2 .= "    <th>$DataByte</th>\n" ;
               $html2 .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$DataByte}{Name}</td>\n" ;
               $html2 .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$DataByte}{Type}</td>\n" ;
               $html2 .= "    <td>\n" ;
               foreach my $Parser ( sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$DataByte}{Match}}) ) {
                  $html2 .= "$Parser: $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Data}{$DataByte}{Match}{$Parser}{Info}<br />\n" ;
               }
               $html2 .= "    </td>\n" ;
               $html2 .= "  </tr>\n" ;
            }
            $html2 .= "</tbody>\n" ;
            $html2 .= "</table>\n" ;
         }
      }
      $html .= "</tbody>\n" ;
      $html .= "</table>\n" ;
      $html .= $html2 if defined $html2 ;
   }
   return $html ;
}

sub www_print_velbus_protocol_print_modules () {
   my $html ;
   $html .= "<table border=1 data-paging=false class=\"datatable\">\n" ;
   $html .= "<thead>\n" ;
   $html .= "  <tr>\n" ;
   $html .= "    <th>Module</th>\n" ;
   $html .= "    <th>Type</th>\n" ;
   $html .= "    <th>Info</th>\n" ;
   $html .= "    <th>Version</th>\n" ;
   $html .= "    <th>Memory</th>\n" ;
   $html .= "    <th>Module name</th>\n" ;
   $html .= "    <th>Channels</th>\n" ;
   $html .= "  </tr>\n" ;
   $html .= "</thead>\n" ;

   foreach my $ModuleType (sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}})) {
      $html .= "  <tr>\n" ;
      $html .= "    <th>$ModuleType</th>\n" ;
      $html .= "    <td><a href=?".&www_make_url("ModuleType=$ModuleType").">$global{Cons}{ModuleTypes}{$ModuleType}{Type}</a></td>\n" ;
      $html .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Info}</td>\n" ;
      $html .= "    <td>$global{Cons}{ModuleTypes}{$ModuleType}{Version}</td>\n" ;
      $html .= "    <td>" ;
      if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{MemoryMatch} ) {
         foreach my $Key (sort keys %{$global{Cons}{ModuleTypes}{$ModuleType}{MemoryMatch}}) {
            $html .= "$global{Cons}{ModuleTypes}{$ModuleType}{MemoryMatch}{$Key}{Build}: $global{Cons}{ModuleTypes}{$ModuleType}{MemoryMatch}{$Key}{Version}<br>\n" ;
         }
      }
      $html .= "    </td>" ;
      my $ModuleName ;
      if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Memory} ) {
         foreach my $Key (sort keys %{$global{Cons}{ModuleTypes}{$ModuleType}{Memory}}) {
            $ModuleName .= $Key . " " ;
         }
      }
      if ( defined $ModuleName ) {
         $html .= "    <td>$ModuleName</td>\n" ;
      } else {
         $html .= "    <td>-</td>\n" ;
      }
      if ( defined $global{Cons}{ModuleTypes}{$ModuleType}{Channels} ) {
         $html .= "    <td>Yes</td>\n" ;
      } else {
         $html .= "    <td>-</td>\n" ;
      }
      $html .= "  </tr>\n" ;
   }

   $html .= "<tbody>\n" ;
   $html .= "</tbody>\n" ;
   $html .= "</table>\n" ;
   return $html ;
}

sub www_openHAB () {
   &openHAB_config () ;
   my $openHAB = &openHAB () ;
   $openHAB =~ s/</&lt;/g ;    # Prepare for html output
   $openHAB =~ s/>/&gt;/g ;    # Prepare for html output
   $openHAB =~ s/\n/<br>\n/g ; # Prepare for html output
   return "$openHAB\n" ;
}

sub www_scan () {
   my $sock = &open_socket ;
   &scan($sock) ;
}

sub www_clear_database  () {
   my $html ;
   $html .= "Recommended procedure:\n" ;
   $html .= "<ul>\n" ;
   $html .= "<li>Stop logger.pl</li>\n" ;
   $html .= "<li>Visit this page</li>\n" ;
   $html .= "<li>Start logger.pl</li>\n" ;
   $html .= "<li>Trigger a scan</li>\n" ;
   $html .= "<li>Get an update of all module</li>\n" ;
   $html .= "</ul>\n" ;
   &clear_database() ;
   return $html ;
}

sub www_update_module_status () {
   my $sock = &open_socket ;
   my $temp = &update_module_status($sock) ;
   return $temp ;
}

# Loop all modules and messages and sort the info per message
sub www_process_messages () { 
   my %data ;

   # Loop all broadcast messages
   foreach my $Message (sort (keys %{$global{Cons}{MessagesBroadCast}}) ) {
      my $Name = $global{Cons}{MessagesBroadCast}{$Message}{Name} ; # Handier var
      my $Info = $global{Cons}{MessagesBroadCast}{$Message}{Info} ; # Handier var
      my $Prio = $global{Cons}{MessagesBroadCast}{$Message}{Prio} ; # Handier var
      $data{BroadCast}{$Message}{Name} = $Name ;
      $data{BroadCast}{$Message}{Info} = $Info ;
      $data{BroadCast}{$Message}{Prio} = $Prio ;
   }

   # Loop all Modules and Message
   foreach my $ModuleType (sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}})) {
      foreach my $Message ( sort {$a cmp $b} keys (%{$global{Cons}{ModuleTypes}{$ModuleType}{Messages}}) ) {
         foreach my $Name (split ";", $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Name}) {
            $data{Module}{$Message}{Name}{$Name} = "yes" ;
         }
         my $Info = $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Info} ; # Handier var
         my $Prio = $global{Cons}{ModuleTypes}{$ModuleType}{Messages}{$Message}{Prio} ; # Handier var
         $data{Module}{$Message}{ModuleType}{$ModuleType} = "yes" ;
         $data{Module}{$Message}{Info}{$Info} = "yes";
         $data{Module}{$Message}{Prio}{$Prio} = "yes";
      }
   }

   # Loop the messages and try to find a type to sort the messages
   foreach my $Message (sort {$a cmp $b} keys %{$data{Module}}) {
      my $type = "rest" ;
      my $Name = join ";", sort keys %{$data{Module}{$Message}{Name}} ;
      if ( $Name =~ /_STATUS/ ) {
         $type = "Status" ;
      } elsif ( $Name =~ /_PROGRAM/ ) {
         $type = "Program" ;
      } elsif ( $Name =~ /_MEMORY/ ) {
         $type = "Memory" ;
      } elsif ( $Name =~ /_NAME_/ ) {
         $type = "Name" ;
      } elsif ( $Name =~ /DIM/ ) {
         $type = "Dimmer" ;
      } elsif ( $Name =~ /RELAY_/ ) {
         $type = "Relay" ;
      } elsif ( $Name =~ /BLIND_/ ) {
         $type = "Blind" ;
      }
      push @{$data{PerType}{$type}}, $Message ;
   }

   return %data ;
}

return 1 ;
