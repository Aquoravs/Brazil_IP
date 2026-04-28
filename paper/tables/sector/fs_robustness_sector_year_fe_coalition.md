# First Stage — Robustness (sector×year FE, coalition)

                                               M+G               M+P
Dependent Var.:                        delta_s_mjt       delta_s_mjt
                                                                    
Z_mayor_coalition_cycle_specific           0.0068          0.0093*  
                                          (0.0055)        (0.0048)  
Z_gov_coalition_cycle_specific            -0.0029                   
                                          (0.0067)                  
Z_pres_coalition_cycle_specific                            0.0127***
                                                          (0.0022)  
Fixed-Effects:                         -----------       -----------
muni_id-cnae_section                           Yes               Yes
cnae_section-year                              Yes               Yes
________________________________       ___________       ___________
S.E.: Clustered                  by: muni. & cnae. by: muni. & cnae.
Observations                             1,372,575         1,372,575
R2                                         0.01291           0.01291

                                             M+G+P
Dependent Var.:                        delta_s_mjt
                                                  
Z_mayor_coalition_cycle_specific         0.0089   
                                        (0.0060)  
Z_gov_coalition_cycle_specific          -0.0019   
                                        (0.0069)  
Z_pres_coalition_cycle_specific          0.0126***
                                        (0.0028)  
Fixed-Effects:                         -----------
muni_id-cnae_section                           Yes
cnae_section-year                              Yes
________________________________       ___________
S.E.: Clustered                  by: muni. & cnae.
Observations                             1,372,575
R2                                         0.01291
---
Signif. codes: 0 '***' 0.01 '**' 0.05 '*' 0.1 ' ' 1
