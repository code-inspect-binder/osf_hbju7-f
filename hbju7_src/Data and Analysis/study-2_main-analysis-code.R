#######################################################################

# Conceptual recplication of Amit et al. (2013, Experiment 2)

#######################################################################

# Load packages ----------------------------------------------------------------

packages <- c("tidyverse", "lme4", "car")

lapply(packages, library, character.only = TRUE)

# Load data --------------------------------------------------------------------

################################################################################

# raw <- read.csv("study-2_raw-data.csv")
# 
# raw <- raw %>%
#   slice(-1, -2) %>% 
#   type_convert()
# 
# raw <- raw %>% 
#   mutate(
#     task = case_when(
#       !is.na(induction_choice_1)  ~ "cooktop",
#       !is.na(speaker_choice_1)    ~ "speaker",
#       !is.na(dishwasher_choice_1) ~ "dishwasher"
#     ),
#     attention_check_filter = case_when(
#       attention_check == "An induction cooktop" & task == "cooktop"    ~ 1,
#       attention_check == "A bluetooth speaker"  & task == "speaker"    ~ 1,
#       attention_check == "A dishwasher"         & task == "dishwasher" ~ 1
#     )
#   )
# 
# replication <- raw %>% 
#   filter(attention_check_filter == 1) %>% 
#   filter(Finished == TRUE) %>% 
#   rename(
#     ID = ResponseId
#   )
# 
# demographics <- read.csv("study-2_demographics.csv") %>% 
#   rename(
#     prolific_ID = participant_id
#   )
# 
# replication <- replication %>% 
#   left_join(demographics, by = "prolific_ID")
# 
# export <- replication %>% 
#   select(
#     ID,
#     task,
#     starts_with("dishwasher_choice"),
#     starts_with("speaker_choice"),
#     starts_with("induction_choice"),
#     starts_with("social_dist_rating"),
#     attention_check,
#     attention_check_filter,
#     why = why_q.,
#     age,
#     country_of_birth = Country.of.Birth,
#     country_of_residence = Current.Country.of.Residence,
#     employment = Employment.Status,
#     first_language = First.Language,
#     sex = Sex,
#     student = Student.Status
#   )
# 
# write.csv(export, "study-2_data-cleaned.csv", row.names = FALSE)

################################################################################

replication <- read.csv("study-2_data-cleaned.csv")

# Wrangle ----------------------------------------------------------------------

choices <- replication %>% 
  pivot_longer(
    cols = c(starts_with("dishwasher_choice"), starts_with("speaker_choice"), starts_with("induction_choice")),
    names_pattern = "(.*)_choice_(.*)",
    names_to = c("choice_task", "target"),
    values_to = "choice"
  ) %>% 
  filter(!is.na(choice))

choices <- choices %>% 
  mutate(
    instructions = case_when(
      choice == "P" ~ 0,
      choice == "T" ~ 1
    )
  )

distance <- replication %>% 
  select(ID, starts_with("social_dist_rating")) %>% 
  pivot_longer(
    cols = starts_with("social_dist_rating"),
    names_pattern = ".*_.*_.*_(.*)",
    names_to = "target",
    values_to = "distance"
  )

choices <- choices %>% 
  left_join(distance, by = c("ID", "target"))

supplement <- choices %>% 
  pivot_wider(
    id_cols     = "ID",
    names_from  = "target",
    names_prefix = "target_",
    values_from = "instructions"
  ) %>% 
  mutate(
    distant = target_1 + target_6 + target_12, 
    close   = target_7 + target_9 + target_14
  )

supplement <- supplement %>% 
  left_join(
    select(replication, ID, task),
    by = "ID"
  )

supplement$task <- as.factor(supplement$task)

contrasts(supplement$task) <- contr.Sum(3)

# Main analyses ----------------------------------------------------------------

## Descriptives

prop_table <- choices %>% 
  group_by(distance) %>% 
  summarise(
    proportion = sum(instructions)/n()
  ) %>% 
  t()

## Mixed effects logistic regression

logistic_model_1 <- glmer(instructions ~ distance + (1|ID) + (1|target) + (1|task), data = choices, family = binomial(link = "logit"))

logistic_model_2 <- glmer(instructions ~ distance + (1 + distance|ID) + (1|target) + (1|task), data = choices, family = binomial(link = "logit"))

logistic_model_3 <- glmer(instructions ~ distance + (1 + distance|ID) + (1|target) + (1 + distance|task), data = choices, family = binomial(link = "logit"), control = glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 100000)))

model_comparison <- anova(logistic_model_1, logistic_model_2, logistic_model_3)

## Mixed ANOVA

distance_factor <- as.factor(c("close", "distant"))

h1_idata <- data.frame(distance_factor)

instructions_bound <- cbind(supplement$close, supplement$distant)

task <- as.factor(supplement$task)

mixed_lm <- lm(instructions_bound ~ task)

h1_mixed_anova <- Anova(mixed_lm, idata = h1_idata, idesign = ~ distance_factor, type = 3)

### Follow-up tests

#### Main effect of distance

t_distance <- t.test(supplement$close, supplement$distant, paired = TRUE)

distance_desc <- supplement %>% 
  summarise(
    mean_close     = mean(close),
    sd_close       = sd(close),
    median_close   = median(close),
    mean_distant   = mean(distant),
    sd_distant     = sd(distant),
    median_distant = median(distant)
  )

#### Interaction of task and distance

distance_desc_task <- supplement %>% 
  group_by(task) %>% 
  summarise(
    mean_close     = mean(close),
    sd_close       = sd(close),
    median_close   = median(close),
    mean_distant   = mean(distant),
    sd_distant     = sd(distant),
    median_distant = median(distant)
  )

sup_cooktop <- supplement %>% 
  filter(task == "cooktop")

t_cooktop <- t.test(sup_cooktop$close, sup_cooktop$distant, paired = TRUE)

sup_dish <- supplement %>% 
  filter(task == "dishwasher")

t_dish <- t.test(sup_dish$close, sup_dish$distant, paired = TRUE)

sup_speaker <- supplement %>% 
  filter(task == "speaker")

t_speaker <- t.test(sup_speaker$close, sup_speaker$distant, paired = TRUE)

#### Partial Omega Squared

omega_sq <- function(aov_mod, N) {
  
  aov_summary <- summary(aov_mod)$univariate.tests
  
  ss_effect   <- aov_summary[, 1] 
  df_effect   <- aov_summary[, 2] 
  ss_error    <- aov_summary[, 3] 
  df_error    <- aov_summary[, 4] 
  
  ms_effect   <- ss_effect/df_effect
  ms_error    <- ss_error/df_error
  
  eta         <- ss_effect / (ss_effect + ss_error)
  omega       <- ( df_effect * (ms_effect - ms_error) ) / ( df_effect * ms_effect + (N + df_effect) * ms_error)
  
  return(list(partial_eta_sq = eta, partial_omega_sq = omega))
  
} 

partial_omega_h1 <- omega_sq(h1_mixed_anova, nrow(mixed_lm$fitted.values))

#### Visualizations

supplement_long <- supplement %>% 
  pivot_longer(
    cols      = c("close", "distant"),
    names_to  = "social_distance",
    values_to = "count"
  )

supplemental_histogram <-
  ggplot(supplement_long,
         aes(
           x = count
         )) +
  facet_grid(task ~ social_distance) +
  geom_histogram(
    binwidth = 1
  ) +
  theme_classic()
