#' generate a shiny app for binary data type
#'
#'This method launch the Shiny app to show results from previous multiple hypothesis testings and allow users to query for details on conspicuous features.
#'Use this function when the condition/explanatory variables have binary data type.
#'
#' @param df A long data.frame with sample measurements across all features
#' @param stats_df A data.frame contains statistics of tests across features; the output from fit_statistics function
#' @param group_list The list of distinct features after splitting the data.frame
#' @param group The name of the column used when initially splitting measurements across features
#' @param value The name of the column used to describe response variable
#'
#' @return A interactive Shiny app interface allow users to explore details of test results
#' @export
#' @import dplyr
#' @import ggplot2
#' @import shiny
#' @importFrom DT datatable formatStyle styleEqual renderDT DTOutput
#' @importFrom magrittr %>%
#'
#' @examples
#' lm_func <- function(x) { lm(log(value) ~ B * F * K, data = x) }
#' code <- function(z) { ifelse(str_detect(z, "\\+"), 1, -1) }
#' fits <- thor %>% mutate(across(B:M, code)) %>% split_dataset(compound) %>% fit_statistics(lm_func, compound)
#' group_list <- unique(thor$compound)
#' brush_plots_binary(thor, fits, group_list, "compound", "value")
brush_plots_binary <- function(df, stats_df, group_list, group, value){
  stats_df_param <- stats_df %>%
    filter(term != "(Intercept)")
  past_candidates <- c("-1")

  set_theme()
  shinyApp(
    ui = fluidPage(
      ## could add a title by adding a new param
      column(
        plotOutput("distPlot", brush = brushOpts(direction = "x", id = "brush")),
        width = 6
      ),

      column(
        plotOutput("plot_g2"),
        width = 6
      ),

      DTOutput("table"),
      selectInput("group", "ID", choices = group_list, multiple = TRUE),
      downloadButton("download", "Download current rows")
    ),

    server = function(input, output, session) {

      brushed_ids <- reactive({
        current_points <- brushedPoints(stats_df_param, input$brush)
        current_points %>%
          select(term, .data[[group]])
      })


      table_data <- reactive({
        current_rows <- stats_df_param %>%
          mutate(statistic = round(statistic, 5)) %>%
          select(.data[[group]], term, statistic) %>%
          filter(.data[[group]] %in% brushed_ids()[[group]]) %>%
          pivot_wider(names_from = term, values_from = statistic)

        if(nrow(current_rows) > 0) {
          current_rows$magnitude <- abs(current_rows[, brushed_ids()$term[1]])
          max <- max(current_rows$magnitude)
          min <- min(current_rows$magnitude)
          stat_term <- as.character(brushed_ids()$term[1])

          current_rows <- stats_df_param %>%
            mutate(statistic = round(statistic, 5)) %>%
            select(.data[[group]], term, statistic) %>%
            pivot_wider(names_from = term, values_from = statistic)
          current_rows$magnitude <- abs(current_rows[, brushed_ids()$term[1]])

          current_rows <- current_rows %>%
            filter(magnitude <= max & magnitude >= min) %>%
            arrange(-magnitude) %>%
            arrange_at(vars(-.data[[group]]:-magnitude)) %>%
            mutate(color = sign(.data[[stat_term]])) %>%
            select(-magnitude)
        }
      })

      output$download <- downloadHandler(
        filename = function() {
          "table_data.csv"
        },
        content = function(fname) {
          write_csv(table_data(), fname)
        }
      )

      output$distPlot <- renderPlot({
        if(is.null(table_data())){
          draw_stats_histogram(stats_df)
        }
        else{

          current_data_po <- stats_df_param %>%
            filter(.data[[group]] %in% (table_data() %>%
                                          filter(color == 1))[[group]])

          current_data_ne <- stats_df_param %>%
            filter(.data[[group]] %in% (table_data() %>%
                                          filter(color == -1))[[group]])

          ggplot(stats_df_param, aes(x = statistic)) +
            geom_histogram(bins = 100) +
            geom_histogram(data = current_data_po, fill = "red", bins = 100) +
            geom_histogram(data = current_data_ne, fill = "orange", bins = 100) +
            scale_y_continuous(expand = c(0, 0, .1, .1)) +
            labs(x = "ANOVA test statistic") +
            facet_wrap(~ term, scales = "free") +
            theme(strip.text = element_text(size = 14))
        }
      })

      output$table <- renderDT({
        if(is.null(table_data())) {
          return()
        }

        datatable(
          table_data(),
          rownames = FALSE,
          filter="top",
          options = list(sDom = '<"top">lrt<"bottom">ip', columnDefs = list(list(visible=FALSE, targets=8)))
        ) %>%
        formatStyle('color', target = 'row', backgroundColor = styleEqual(c(-1,1), c('#ffc14e', '#ff7676')))
      })

      output$plot_g2 <- renderPlot({
        cur_groups <- unique(input$group)
        if (length(cur_groups) != 0) {
          x_small <- df %>%
            filter(.data[[group]] %in%  cur_groups) %>%
            mutate(group = factor(.data[[group]], levels = cur_groups))
        } else {
          x_small <- df[sample(1:nrow(df), 1000), ]
        }

        p <- ggplot(x_small) +
          geom_point(aes(condition, value)) +
          scale_y_log10(breaks = 10 ^ (5:9)) +
          labs(y =  "Intensity Values") +
          theme(axis.text.x = element_text(angle = 90))

        if (length(cur_groups) != 0) {
          p <- p + facet_wrap(~ group, scales = "free_y")
        }
        p
      })

      observeEvent(input$brush, {
        if(is.null(table_data())){
          candidates = NULL
        } else{
          candidates <- table_data()[[group]]
        }

        if (!all(candidates == past_candidates)) {
          selected_ids <- head(candidates, 12)
          past_candidates <- candidates
        } else {
          selected_ids <- input$group
        }

        updateSelectInput(session, "group", choices = candidates, selected = selected_ids)
      })
    },
  )
}
