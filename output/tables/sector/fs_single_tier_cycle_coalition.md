# First Stage — Single Tiers (cycle-specific, muni×year FE, coalition)

                                             Mayor          Governor
Dependent Var.:                        delta_s_mjt       delta_s_mjt
                                                                    
Z_mayor_coalition_cycle_specific         0.0282***                  
                                        (0.0080)                    
Z_gov_coalition_cycle_specific                              -0.0039 
                                                            (0.0095)
Z_pres_coalition_cycle_specific                                     
                                                                    
Fixed-Effects:                         -----------       -----------
muni_id-cnae_section                           Yes               Yes
muni_id-year                                   Yes               Yes
________________________________       ___________       ___________
S.E.: Clustered                  by: muni. & cnae. by: muni. & cnae.
Observations                             1,372,575         1,372,575
R2                                         0.03691           0.03690

                                         President
Dependent Var.:                        delta_s_mjt
                                                  
Z_mayor_coalition_cycle_specific                  
                                                  
Z_gov_coalition_cycle_specific                    
                                                  
Z_pres_coalition_cycle_specific           -0.0225 
                                          (0.0151)
Fixed-Effects:                         -----------
muni_id-cnae_section                           Yes
muni_id-year                                   Yes
________________________________       ___________
S.E.: Clustered                  by: muni. & cnae.
Observations                             1,372,575
R2                                         0.03691
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
