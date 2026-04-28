# First Stage — Single Tiers (cycle-specific, muni×year FE, party)

                                         Mayor          Governor
Dependent Var.:                    delta_s_mjt       delta_s_mjt
                                                                
Z_mayor_party_cycle_specific         0.0476***                  
                                    (0.0166)                    
Z_gov_party_cycle_specific                            -0.0314***
                                                      (0.0101)  
Z_pres_party_cycle_specific                                     
                                                                
Fixed-Effects:                     -----------       -----------
muni_id-cnae_section                       Yes               Yes
muni_id-year                               Yes               Yes
____________________________       ___________       ___________
S.E.: Clustered              by: muni. & cnae. by: muni. & cnae.
Observations                         1,372,575         1,372,575
R2                                     0.03692           0.03691

                                     President
Dependent Var.:                    delta_s_mjt
                                              
Z_mayor_party_cycle_specific                  
                                              
Z_gov_party_cycle_specific                    
                                              
Z_pres_party_cycle_specific            0.0601*
                                      (0.0337)
Fixed-Effects:                     -----------
muni_id-cnae_section                       Yes
muni_id-year                               Yes
____________________________       ___________
S.E.: Clustered              by: muni. & cnae.
Observations                         1,372,575
R2                                     0.03691
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
